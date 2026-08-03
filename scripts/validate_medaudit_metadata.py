#!/usr/bin/env python3
"""Validate MedAudit GitOps image/version metadata without third-party packages."""

from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

SHA = re.compile(r"^[0-9a-f]{40}$")
STAGING_SHA = re.compile(r"^staging-([0-9a-f]{40})$")
IMAGE = re.compile(r"^ghcr\.io/irupe-consultores/hhccia-(front|core|adapter-datatech):(.+)$")

EXPECTED = {
    "front": {"BUILD_SHA": "front"},
    "core": {
        "BUILD_SHA": "core",
        "FRONT_BUILD_SHA": "front",
        "ADAPTER_BUILD_SHA": "adapter-datatech",
        "FRONT_IMAGE": "front",
        "CORE_IMAGE": "core",
        "ADAPTER_IMAGE": "adapter-datatech",
    },
}

CORE_BUILD_VARIABLES = {
    "BUILD_SHA": "core",
    "FRONT_BUILD_SHA": "front",
    "ADAPTER_BUILD_SHA": "adapter-datatech",
}


def _value_for(env_text: str, name: str) -> str | None:
    match = re.search(
        rf"(?m)^\s*- name: {re.escape(name)}\s*\n\s+value: [\"']?([^\"'\s]+)",
        env_text,
    )
    return match.group(1) if match else None


def _deployment(path: Path) -> str | None:
    for document in path.read_text().split("\n---"):
        if re.search(r"(?m)^kind: Deployment\s*$", document):
            return document
    return None


def _images(document: str) -> dict[str, str]:
    result = {}
    for match in re.finditer(r"(?m)^\s+image: (ghcr\.io/irupe-consultores/[^\s]+)", document):
        image = match.group(1)
        parsed = IMAGE.match(image)
        if parsed:
            result[parsed.group(1)] = image
    return result


def _sha_from_image(image: str) -> str | None:
    parsed = IMAGE.match(image)
    if not parsed:
        return None
    tag = parsed.group(2)
    staging = STAGING_SHA.fullmatch(tag)
    if staging:
        return staging.group(1)
    return tag if SHA.fullmatch(tag) else None


def validate(root: Path) -> list[str]:
    errors: list[str] = []
    discovered: dict[str, dict[str, str]] = {}
    for environment, directory in (("prod", "hhccia-v2"), ("staging", "hhccia-staging")):
        base = root / "src" / directory
        files = {
            "front": base / "hhccia-front.yaml",
            "core": base / "hhccia-core.yaml",
            "adapter-datatech": base / "hhccia-adapter-datatech.yaml",
        }
        for component, path in files.items():
            if not path.exists():
                errors.append(f"{path}: manifest is missing")
                continue
            document = _deployment(path)
            if document is None:
                errors.append(f"{path}: Deployment is missing")
                continue
            images = _images(document)
            image = images.get(component)
            if image is None:
                errors.append(f"{path}: image for {component} is missing or invalid")
                continue
            sha = _sha_from_image(image)
            if sha is None:
                errors.append(f"{path}: image tag is not a 40-character SHA (or staging-SHA): {image}")
                continue
            discovered.setdefault(environment, {})[component] = sha
            parsed_image = IMAGE.match(image)
            assert parsed_image is not None
            if environment == "staging" and not parsed_image.group(2).startswith("staging-"):
                errors.append(f"{path}: staging image tag is not staging-SHA: {image}")
            if environment == "prod" and parsed_image.group(2).startswith("staging-"):
                errors.append(f"{path}: prod image tag must not be staging-SHA: {image}")

            if component in ("front", "core"):
                env = document[document.find("          env:"):]
                actual_env = _value_for(env, "APP_ENV")
                if actual_env != environment:
                    errors.append(f"{path}: APP_ENV={actual_env!r}, expected {environment!r}")
                for variable, image_component in EXPECTED[component].items():
                    if variable == "APP_ENV":
                        continue
                    actual = _value_for(env, variable)
                    if variable.endswith("_IMAGE"):
                        expected_image = images.get(image_component) if image_component == component else None
                        # Cross-workload image variables must be compared with the
                        # sibling Deployment's exact current image below.
                        if expected_image is None:
                            expected_image = None
                        if actual is None:
                            errors.append(f"{path}: {variable} is missing")
                        elif not IMAGE.fullmatch(actual):
                            errors.append(f"{path}: {variable} is not a valid image reference: {actual}")
                        elif actual != expected_image and image_component == component:
                            errors.append(f"{path}: {variable}={actual} does not match current image {expected_image}")
                    else:
                        expected = discovered.get(environment, {}).get(image_component)
                        if actual is None:
                            errors.append(f"{path}: {variable} is missing")
                        elif not SHA.fullmatch(actual):
                            errors.append(f"{path}: {variable} is not a SHA: {actual}")
                        elif expected is not None and actual != expected:
                            errors.append(f"{path}: {variable}={actual} does not match {image_component} image SHA {expected}")

        # Cross-component metadata checks after all three current tags are known.
        core_path = base / "hhccia-core.yaml"
        document = _deployment(core_path) if core_path.exists() else None
        if document and environment in discovered:
            env = document[document.find("          env:"):]
            # Validate all core build metadata only after every sibling image
            # has been discovered. The per-workload checks above cannot do
            # this for ADAPTER_BUILD_SHA because the adapter is visited after
            # core in the manifest list.
            for variable, component in CORE_BUILD_VARIABLES.items():
                actual = _value_for(env, variable)
                expected = discovered[environment].get(component)
                if actual is None:
                    errors.append(f"{core_path}: {variable} is missing")
                elif not SHA.fullmatch(actual):
                    errors.append(f"{core_path}: {variable} is not a SHA: {actual}")
                elif expected is not None and actual != expected:
                    errors.append(f"{core_path}: {variable}={actual} does not match {component} image SHA {expected}")
            for variable, component in (("FRONT_IMAGE", "front"), ("CORE_IMAGE", "core"), ("ADAPTER_IMAGE", "adapter-datatech")):
                actual = _value_for(env, variable)
                target = None
                if component in discovered[environment]:
                    # Reconstructing from the manifest avoids accepting a stale
                    # variable even when only its bare SHA happens to match.
                    target_path = base / ("hhccia-front.yaml" if component == "front" else "hhccia-core.yaml" if component == "core" else "hhccia-adapter-datatech.yaml")
                    target_doc = _deployment(target_path)
                    target = next(iter(_images(target_doc).values()), None) if target_doc else None
                if actual != target:
                    errors.append(f"{core_path}: {variable}={actual!r} does not match current image {target!r}")

    for environment, components in discovered.items():
        print(f"{environment}: " + ", ".join(f"{name}={sha}" for name, sha in sorted(components.items())))
    return errors


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root", nargs="?", type=Path, default=Path(__file__).resolve().parents[1])
    args = parser.parse_args()
    errors = validate(args.root)
    if errors:
        for error in errors:
            print(f"ERROR: {error}", file=sys.stderr)
        return 1
    print("MedAudit metadata validation passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

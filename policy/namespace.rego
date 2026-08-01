# Policies for Namespace resources.
# Every namespace defined in this repo must carry Pod Security Standards
# labels so the kubelet enforces at least the baseline profile.

package main

import rego.v1

is_namespace if input.kind == "Namespace"

deny contains msg if {
	is_namespace
	not input.metadata.labels["pod-security.kubernetes.io/enforce"]
	msg := sprintf("Namespace/%s: must set pod-security.kubernetes.io/enforce label", [input.metadata.name])
}

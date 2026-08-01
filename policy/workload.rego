# Policies for workload kinds: Deployment, DaemonSet, StatefulSet, CronJob, Job.
# deny  = hard gate (CI fails)
# warn  = advisory (tracks progress toward the restricted PSS profile)

package main

import rego.v1

workload_kinds := {"Deployment", "DaemonSet", "StatefulSet", "CronJob", "Job"}

is_workload if input.kind in workload_kinds

pod_spec := input.spec.jobTemplate.spec.template.spec if {
	is_workload
	input.kind == "CronJob"
}

pod_spec := input.spec.template.spec if {
	is_workload
	input.kind != "CronJob"
}

all_containers contains c if {
	is_workload
	c := pod_spec.containers[_]
}

all_containers contains c if {
	is_workload
	c := pod_spec.initContainers[_]
}

# ---------------------------------------------------------------------------
# Exceptions — workloads that legitimately cannot meet a rule today.
# ---------------------------------------------------------------------------

# Need a mounted SA token for scoped k8s API access (Role: jobs/cronjobs/pods),
# or are legacy backup jobs that predate the hardening pass.
automount_exceptions := {
	"hhccia-prestaciones-ui",
	"hhccia-guardia-pediatria-ui",
	"vaultwarden-sqlite-backup",
}

# Upstream-managed images whose charts/entrypoints don't expose resource knobs,
# or legacy backup jobs. Tracked for a future hardening pass.
resource_exceptions := {
	"authentik-server",
	"authentik-worker",
	"vaultwarden-sqlite-backup",
}

# Init containers that are trivial file-copiers (busybox one-liners).
init_resource_exceptions := {
	"copy-gmail-json",
}

# ---------------------------------------------------------------------------
# deny — hard gate
# ---------------------------------------------------------------------------

deny contains msg if {
	is_workload
	c := all_containers[_]
	c.securityContext.privileged == true
	msg := sprintf("%s/%s: container '%s' must not be privileged", [input.kind, input.metadata.name, c.name])
}

deny contains msg if {
	is_workload
	pod_spec.hostNetwork == true
	msg := sprintf("%s/%s: hostNetwork is not allowed", [input.kind, input.metadata.name])
}

deny contains msg if {
	is_workload
	pod_spec.hostPID == true
	msg := sprintf("%s/%s: hostPID is not allowed", [input.kind, input.metadata.name])
}

deny contains msg if {
	is_workload
	pod_spec.hostIPC == true
	msg := sprintf("%s/%s: hostIPC is not allowed", [input.kind, input.metadata.name])
}

deny contains msg if {
	is_workload
	not input.metadata.name in automount_exceptions
	not pod_spec.automountServiceAccountToken == false
	msg := sprintf("%s/%s: automountServiceAccountToken must be false", [input.kind, input.metadata.name])
}

deny contains msg if {
	is_workload
	not input.metadata.name in resource_exceptions
	c := pod_spec.containers[_]
	not c.resources.requests
	msg := sprintf("%s/%s: container '%s' must have resources.requests", [input.kind, input.metadata.name, c.name])
}

deny contains msg if {
	is_workload
	not input.metadata.name in resource_exceptions
	c := pod_spec.containers[_]
	not c.resources.limits
	msg := sprintf("%s/%s: container '%s' must have resources.limits", [input.kind, input.metadata.name, c.name])
}

deny contains msg if {
	is_workload
	not input.metadata.name in resource_exceptions
	c := pod_spec.initContainers[_]
	not c.name in init_resource_exceptions
	not c.resources.requests
	msg := sprintf("%s/%s: initContainer '%s' must have resources.requests", [input.kind, input.metadata.name, c.name])
}

deny contains msg if {
	is_workload
	not input.metadata.name in resource_exceptions
	c := pod_spec.initContainers[_]
	not c.name in init_resource_exceptions
	not c.resources.limits
	msg := sprintf("%s/%s: initContainer '%s' must have resources.limits", [input.kind, input.metadata.name, c.name])
}

# ---------------------------------------------------------------------------
# warn — advisory (restricted PSS profile targets)
# ---------------------------------------------------------------------------

warn contains msg if {
	is_workload
	c := all_containers[_]
	not c.securityContext.allowPrivilegeEscalation == false
	msg := sprintf("%s/%s: container '%s' should set allowPrivilegeEscalation: false", [input.kind, input.metadata.name, c.name])
}

warn contains msg if {
	is_workload
	not pod_spec.securityContext.runAsNonRoot == true
	c := all_containers[_]
	not c.securityContext.runAsNonRoot == true
	msg := sprintf("%s/%s: container '%s' should set runAsNonRoot: true (pod or container level)", [input.kind, input.metadata.name, c.name])
}

warn contains msg if {
	is_workload
	c := all_containers[_]
	not _drops_all(c)
	msg := sprintf("%s/%s: container '%s' should drop ALL capabilities", [input.kind, input.metadata.name, c.name])
}

warn contains msg if {
	is_workload
	not pod_spec.securityContext.seccompProfile.type == "RuntimeDefault"
	c := all_containers[_]
	not c.securityContext.seccompProfile.type == "RuntimeDefault"
	msg := sprintf("%s/%s: container '%s' should set seccompProfile: RuntimeDefault", [input.kind, input.metadata.name, c.name])
}

_drops_all(c) if {
	caps := {cap | cap := c.securityContext.capabilities.drop[_]}
	"ALL" in caps
}

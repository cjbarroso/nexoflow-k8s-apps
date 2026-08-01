# Policies for Argo CD Application resources.
# Every app must be fully automated (prune + selfHeal) so the cluster
# converges to the Git state without manual intervention.

package main

import rego.v1

is_application if input.kind == "Application"

deny contains msg if {
	is_application
	input.spec.syncPolicy.automated.prune != true
	msg := sprintf("Application/%s: syncPolicy.automated.prune must be true", [input.metadata.name])
}

deny contains msg if {
	is_application
	input.spec.syncPolicy.automated.selfHeal != true
	msg := sprintf("Application/%s: syncPolicy.automated.selfHeal must be true", [input.metadata.name])
}

{{- define "fleet-member.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "fleet-member.validateCommon" -}}
{{- $dns := "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" -}}
{{- $tenantRe := "^[a-z][a-z0-9]*$" -}}
{{- $mode := default "agent" .Values.mode -}}
{{- if not (has $mode (list "agent" "cluster")) -}}
{{- fail (printf "mode must be 'agent' or 'cluster', got %q" $mode) -}}
{{- end -}}
{{- $orgName := required "org.name is required" .Values.org.name -}}
{{- if or (gt (len $orgName) 40) (not (regexMatch $dns $orgName)) -}}
{{- fail (printf "org.name %q must be a DNS-1123 label (max 40 chars)" $orgName) -}}
{{- end -}}
{{- if has $orgName (list "hub-cluster" "in-cluster") -}}
{{- fail (printf "org.name %q is reserved by the hub" $orgName) -}}
{{- end -}}
{{- $tenant := required "org.tenant is required" .Values.org.tenant -}}
{{- if not (regexMatch $tenantRe $tenant) -}}
{{- fail (printf "org.tenant %q must use lowercase letters and digits only" $tenant) -}}
{{- end -}}
{{- with .Values.org.environment -}}
{{- if not (regexMatch $dns .) -}}
{{- fail (printf "org.environment %q must be a DNS-1123 label" .) -}}
{{- end -}}
{{- end -}}
{{- end }}

{{- define "fleet-member.validate" -}}
{{- include "fleet-member.validateCommon" . -}}
{{- $dns := "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" -}}
{{- $expectedServer := default "https://kubernetes.default.svc.cluster.local" .Values.clusterSecret.server -}}
{{- $agentName := required "agent.name is required" .Values.agent.name -}}
{{- $_ := required "agent.identifier is required" .Values.agent.identifier -}}
{{- $_ := required "agent.accountId is required" .Values.agent.accountId -}}
{{- $_ := required "agent.apiKeySecretRef is required" .Values.agent.apiKeySecretRef -}}
{{- $_ := required "agent.tokenSecretRef is required" .Values.agent.tokenSecretRef -}}
{{- $reserved := list "default" "platform" "platform-admin" "kube" "hga" "spoke" "org" "argocd" "external" "openbao" "cert" "ingress" "monitoring" "fleet" -}}
{{- $seenNamespaces := dict -}}
{{- range $team, $t := .Values.teams -}}
{{- if has $team $reserved -}}
{{- fail (printf "teams: %q is reserved and cannot be used as a team name" $team) -}}
{{- end -}}
{{- if not (regexMatch $dns $team) -}}
{{- fail (printf "teams: %q must be a DNS-1123 label" $team) -}}
{{- end -}}
{{- $prefix := printf "%s-" $team -}}
{{- if or (hasPrefix $prefix $.Release.Namespace) (eq $team $.Release.Namespace) (hasPrefix $prefix $agentName) -}}
{{- fail (printf "teams: %q prefix overlaps the agent namespace %q or agent name %q" $team $.Release.Namespace $agentName) -}}
{{- end -}}
{{- range $other, $_ := $.Values.teams -}}
{{- if and (ne $other $team) (hasPrefix (printf "%s-" $other) $team) -}}
{{- fail (printf "teams: %q overlaps prefix of %q" $team $other) -}}
{{- end -}}
{{- end -}}
{{- $_ := required (printf "teams.%s.projectId is required" $team) $t.projectId -}}
{{- range (default (list) $t.sourceRepos) -}}
{{- if or (contains "*" .) (contains "?" .) (contains "[" .) (hasPrefix "!" .) -}}
{{- fail (printf "teams.%s.sourceRepos: %q is a pattern; list exact repository URLs" $team .) -}}
{{- end -}}
{{- end -}}
{{- range (default (list) $t.destinations) -}}
{{- $server := default $expectedServer .server -}}
{{- if ne $server $expectedServer -}}
{{- fail (printf "teams.%s.destinations: server %q must match clusterSecret.server %q" $team $server $expectedServer) -}}
{{- end -}}
{{- if not (hasPrefix $prefix (default "" .namespace)) -}}
{{- fail (printf "teams.%s.destinations: namespace %q must start with %q" $team .namespace $prefix) -}}
{{- end -}}
{{- end -}}
{{- range (default (list) $t.namespaces) -}}
{{- if or (not (hasPrefix $prefix .)) (not (regexMatch $dns .)) (gt (len .) 63) -}}
{{- fail (printf "teams.%s.namespaces: %q must be a valid DNS-1123 namespace starting with %q" $team . $prefix) -}}
{{- end -}}
{{- if hasKey $seenNamespaces . -}}
{{- fail (printf "teams.%s.namespaces: duplicate namespace %q" $team .) -}}
{{- end -}}
{{- $_ := set $seenNamespaces . true -}}
{{- end -}}
{{- end -}}
{{- end }}

{{- define "fleet-member.allNamespaces" -}}
{{- $all := list -}}
{{- range $team, $t := .Values.teams -}}
{{- range (default (list) $t.namespaces) -}}
{{- $all = append $all . -}}
{{- end -}}
{{- end -}}
{{- join "," (sortAlpha (uniq $all)) -}}
{{- end }}

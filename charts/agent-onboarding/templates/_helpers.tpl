{{- define "agent-onboarding.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "agent-onboarding.validate" -}}
{{- $dns := "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" -}}
{{- $tenantRe := "^[a-z][a-z0-9]*$" -}}
{{- $a := .Values.agent -}}
{{- $agentName := required "agent.name is required" $a.name -}}
{{- if or (gt (len $agentName) 40) (not (regexMatch $dns $agentName)) -}}
{{- fail (printf "agent.name %q must be a DNS-1123 label (max 40 chars)" $agentName) -}}
{{- end -}}
{{- if has $agentName (list "hub-cluster" "in-cluster" "hga-hub-agent" "hga-system") -}}
{{- fail (printf "agent.name %q is reserved by the hub" $agentName) -}}
{{- end -}}
{{- $tenant := required "agent.tenant is required" $a.tenant -}}
{{- if not (regexMatch $tenantRe $tenant) -}}
{{- fail (printf "agent.tenant %q must use lowercase letters and digits only" $tenant) -}}
{{- end -}}
{{- with $a.environment -}}
{{- if not (regexMatch $dns .) -}}
{{- fail (printf "agent.environment %q must be a DNS-1123 label" .) -}}
{{- end -}}
{{- end -}}
{{- $_ := required "agent.identifier is required" $a.identifier -}}
{{- $_ := required "agent.accountId is required" $a.accountId -}}
{{- $_ := required "agent.apiKeySecretRef is required" $a.apiKeySecretRef -}}
{{- $_ := required "agent.tokenSecretRef is required" $a.tokenSecretRef -}}
{{- $reserved := list "default" "platform" "platform-admin" "kube" "hga" "spoke" "org" "argocd" "external" "openbao" "cert" "ingress" "monitoring" "fleet" -}}
{{- range $team, $t := .Values.teams -}}
{{- if has $team $reserved -}}
{{- fail (printf "teams: %q is reserved and cannot be used as a team name" $team) -}}
{{- end -}}
{{- if not (regexMatch $dns $team) -}}
{{- fail (printf "teams: %q must be a DNS-1123 label" $team) -}}
{{- end -}}
{{- $prefix := printf "%s-" $team -}}
{{- if or (hasPrefix $prefix $.Release.Namespace) (eq $team $.Release.Namespace) (hasPrefix $prefix $agentName) (eq $team $agentName) -}}
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
{{- if and .server (or (eq .server "*") (eq .server "https://kubernetes.default.svc")) -}}
{{- fail (printf "teams.%s.destinations: server %q is forbidden; use explicit cluster URL or cluster name" $team .server) -}}
{{- end -}}
{{- if and .name (eq .name "*") -}}
{{- fail (printf "teams.%s.destinations: name %q is too broad; specify a cluster name or tenant prefix" $team .name) -}}
{{- end -}}
{{- if not (hasPrefix $prefix (default "" .namespace)) -}}
{{- fail (printf "teams.%s.destinations: namespace %q must start with %q" $team .namespace $prefix) -}}
{{- end -}}
{{- end -}}
{{- end -}}
{{- end }}

{{- define "fleet-secret.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "fleet-secret.validateCommon" -}}
{{- $dns := "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" -}}
{{- $tenantRe := "^[a-z][a-z0-9]*$" -}}
{{- $mode := default "local" .Values.mode -}}
{{- if not (has $mode (list "local" "remote")) -}}
{{- fail (printf "mode must be 'local' or 'remote', got %q" $mode) -}}
{{- end -}}
{{- $name := required "cluster.name is required" .Values.cluster.name -}}
{{- if or (gt (len $name) 40) (not (regexMatch $dns $name)) -}}
{{- fail (printf "cluster.name %q must be a DNS-1123 label (max 40 chars)" $name) -}}
{{- end -}}
{{- if has $name (list "hub-cluster" "in-cluster") -}}
{{- fail (printf "cluster.name %q is reserved by the hub" $name) -}}
{{- end -}}
{{- with .Values.tenant -}}
{{- if not (regexMatch $tenantRe .) -}}
{{- fail (printf "tenant %q must use lowercase letters and digits only" .) -}}
{{- end -}}
{{- end -}}
{{- with .Values.environment -}}
{{- if not (regexMatch $dns .) -}}
{{- fail (printf "environment %q must be a DNS-1123 label" .) -}}
{{- end -}}
{{- end -}}
{{- end }}

{{- define "fleet-secret.validateLocal" -}}
{{- include "fleet-secret.validateCommon" . -}}
{{- $dns := "^[a-z0-9]([-a-z0-9]*[a-z0-9])?$" -}}
{{- $_ := required "tenant is required when mode is local" .Values.tenant -}}
{{- $server := default "https://kubernetes.default.svc.cluster.local" .Values.local.server -}}
{{- if eq $server "https://kubernetes.default.svc" -}}
{{- fail "local.server cannot be https://kubernetes.default.svc (inClusterEnabled is false); use https://kubernetes.default.svc.cluster.local" -}}
{{- end -}}
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
{{- if or (hasPrefix $prefix $.Release.Namespace) (eq $team $.Release.Namespace) -}}
{{- fail (printf "teams: %q prefix overlaps the target agent namespace %q" $team $.Release.Namespace) -}}
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

{{- define "fleet-secret.allNamespaces" -}}
{{- $all := list -}}
{{- range $team, $t := .Values.teams -}}
{{- range (default (list) $t.namespaces) -}}
{{- $all = append $all . -}}
{{- end -}}
{{- end -}}
{{- join "," (sortAlpha (uniq $all)) -}}
{{- end }}

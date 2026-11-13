{{- define "org-platform.labels" -}}
helm.sh/chart: {{ printf "%s-%s" .Chart.Name .Chart.Version }}
app.kubernetes.io/name: {{ .Chart.Name }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{- define "org-platform.validate" -}}
{{- if not .Values.workloadNamespaces }}
{{- fail "workloadNamespaces is required and must not be empty" }}
{{- end }}
{{- if .Values.remoteCluster }}
{{- if or (not .Values.clusterName) (eq .Values.clusterName "hub-cluster") }}
{{- fail "remoteCluster needs clusterName set to the remote cluster's Secret name, not hub-cluster" }}
{{- end }}
{{- /* Remote mode creates nothing on the hub, so the hub-namespace checks do
not apply. The wall is on the remote cluster: its Secret's token may only
write in the namespaces its RoleBindings grant. */}}
{{- else }}
{{- if has .Release.Namespace .Values.workloadNamespaces }}
{{- fail (printf "workloadNamespaces must not contain the Argo CD namespace %q: that would let the org write to its own Argo CD" .Release.Namespace) }}
{{- end }}
{{- /* Without this an org file could list kube-system or another org's
namespace and the platform would grant full control there. */}}
{{- $prefix := printf "%s-" .Release.Namespace }}
{{- range .Values.workloadNamespaces }}
{{- if not (hasPrefix $prefix .) }}
{{- fail (printf "workload namespace %q must start with %q: an org may only use namespaces under its own name" . $prefix) }}
{{- end }}
{{- end }}
{{- end }}
{{- $seen := dict }}
{{- range (.Values.gitopsAgent).projectMappings }}
{{- if eq .appProject "default" }}
{{- fail "gitopsAgent.projectMappings appProject \"default\" is reserved: org-platform locks it" }}
{{- end }}
{{- if hasKey $seen .appProject }}
{{- fail (printf "gitopsAgent.projectMappings contains duplicate appProject %q" .appProject) }}
{{- end }}
{{- $_ := set $seen .appProject true }}
{{- end }}
{{- end }}

{{- define "quinta.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- /*
  fullnameOverride existe para que o chart produza exatamente os mesmos nomes
  que os manifests de k8s/base (quinta-web). Sem isto, uma release chamada
  "quinta" geraria "quinta-quinta" — e o cluster ficaria com dois conjuntos de
  objetos a servir a mesma aplicação.
*/ -}}
{{- define "quinta.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name (include "quinta.name" .) | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}

{{- define "quinta.labels" -}}
app.kubernetes.io/name: {{ include "quinta.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
app.kubernetes.io/part-of: alta-disponibilidade
{{- end -}}

{{- define "quinta.selectorLabels" -}}
app.kubernetes.io/name: {{ include "quinta.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

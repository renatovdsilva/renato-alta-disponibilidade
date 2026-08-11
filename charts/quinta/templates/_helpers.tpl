{{- define "quinta.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{- define "quinta.fullname" -}}
{{- printf "%s-%s" .Release.Name (include "quinta.name" .) | trunc 63 | trimSuffix "-" -}}
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

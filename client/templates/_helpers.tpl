{{/*
Expand the name of the chart.
*/}}
{{- define "zenith-client.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "zenith-client.fullname" -}}
{{- if .Values.fullnameOverride }}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- $name := default .Chart.Name .Values.nameOverride }}
{{- if contains $name .Release.Name }}
{{- .Release.Name | trunc 63 | trimSuffix "-" }}
{{- else }}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" }}
{{- end }}
{{- end }}
{{- end }}

{{/*
Create chart name and version as used by the chart label.
*/}}
{{- define "zenith-client.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "zenith-client.labels" -}}
helm.sh/chart: {{ include "zenith-client.chart" . }}
{{ include "zenith-client.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels
*/}}
{{- define "zenith-client.selectorLabels" -}}
app.kubernetes.io/name: {{ include "zenith-client.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}

{{- define "zenith-client.config" -}}
ssh_key: |
  {{- required "ssh private key is required" .Values.zenithClient.sshKey.private | nindent 2 }}
ssh_key.pub: |
  {{- required "ssh public key is required" .Values.zenithClient.sshKey.public | nindent 2 }}
client.yaml: |
  {{- tpl (toYaml .Values.zenithClient.config) . | nindent 2 }}
  forwardToPort: 8080
{{- end }}

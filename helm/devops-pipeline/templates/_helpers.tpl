{{/*
Helper templates for the devops-pipeline chart.
These define reusable names and labels so we don't hardcode names
like "flask-app" directly in deployment.yaml / service.yaml (as we
did with plain kubectl in v2). Instead, names are generated per
Helm Release, so installing this chart separately into dev/staging/
production namespaces produces unique, non-conflicting resource names.
*/}}

{{/*
Expand the name of the chart.
*/}}
{{- define "devops-pipeline.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Create a default fully qualified app name.
We truncate at 63 chars because some Kubernetes name fields are limited to this (by the DNS naming spec).
If release name contains chart name it will be used as a full name.
*/}}
{{- define "devops-pipeline.fullname" -}}
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
{{- define "devops-pipeline.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" }}
{{- end }}

{{/*
Common labels
*/}}
{{- define "devops-pipeline.labels" -}}
helm.sh/chart: {{ include "devops-pipeline.chart" . }}
{{ include "devops-pipeline.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- end }}

{{/*
Selector labels.
This is the label Pods get and the label the Service uses to find them,
equivalent to the hardcoded "app: flask-app" label used in v2.
*/}}
{{- define "devops-pipeline.selectorLabels" -}}
app.kubernetes.io/name: {{ include "devops-pipeline.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end }}
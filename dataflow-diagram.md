---
title: Solution Dataflow Architecture
description: Runtime telemetry and supporting dependency flows for the GitHub Copilot usage dashboard
ms.date: 2026-09-08
ms.topic: architecture
---

## Solution Dataflow Architecture

```mermaid
flowchart TB
    vscode["VS Code<br/>GitHub Copilot"]
    viewer["Dashboard viewer"]

    subgraph rg["Azure resource group"]
        direction TB
        acr[("Azure Container Registry")]
        identity["Collector managed identity"]
        kv["Azure Key Vault"]
        ai["Application Insights"]
        law[("Log Analytics workspace")]
        grafana["Azure Managed Grafana"]

        subgraph vnet["Virtual network"]
            direction TB
            subgraph aca_subnet["Container Apps delegated subnet"]
                subgraph collector["OTel Collector on Azure Container Apps"]
                    direction TB
                    receiver["OTLP receiver"]
                    processors["Batch and attribute processors"]
                    monitor_exporter["Azure Monitor exporter"]
                    debug_exporter["Debug exporter"]
                end
            end

            subgraph pe_subnet["Private endpoints subnet"]
                kv_pe["Key Vault private endpoint"]
            end
        end

        aca_logs["Container Apps logs"]
    end

    vscode -->|"OTLP/HTTP traces and metrics<br/>public HTTPS ingress :4318"| receiver
    receiver --> processors
    processors -->|"traces and metrics"| monitor_exporter
    monitor_exporter -->|"Azure Monitor ingestion"| ai
    ai -->|"workspace-based telemetry tables"| law
    processors -->|"traces"| debug_exporter
    debug_exporter --> aca_logs
    aca_logs -->|"platform and collector logs"| law
    law <-->|"KQL queries and results"| grafana
    grafana -->|"dashboard over HTTPS"| viewer

    acr -. "collector image" .-> collector
    identity -. "AcrPull" .-> acr
    identity -. "Key Vault Secrets User" .-> kv
    kv -. "Application Insights connection string" .-> kv_pe
    kv_pe -. "private secret read" .-> monitor_exporter
```

### Legend

* Solid arrows represent runtime telemetry, query, or user-interface data flow.
* Dashed arrows represent image, identity, or secret dependencies used to start and configure the collector.
* Subgraphs represent the Azure resource group, virtual network, delegated subnet, private endpoint subnet, and collector process boundaries.

### Key Relationships

* VS Code sends GitHub Copilot traces and metrics to the collector through public OTLP/HTTP ingress on port 4318.
* The collector batches telemetry, adds the `environment=prod` attribute, and exports it to Application Insights through the Azure Monitor exporter.
* Application Insights stores workspace-based telemetry in Log Analytics, where the Grafana Azure Monitor data source runs KQL queries.
* The trace debug exporter writes diagnostic output to Container Apps logs, which also flow to the Log Analytics workspace.
* The collector uses its managed identity to pull its image from Azure Container Registry and read the Application Insights connection string from Key Vault through a private endpoint.

### Scope Notes

* Terraform provisioning traffic and optional dashboard import are deployment-time flows and are outside this runtime dataflow view.
* The collector configuration also enables OTLP/gRPC on port 4317, but the deployed Container App ingress targets OTLP/HTTP on port 4318.

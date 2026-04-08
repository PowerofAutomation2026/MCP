# 🛡️ Microsoft Purview MCP Server

### AI-Powered Compliance & Auditing — Automated by Claude & Copilot Studio

> *What used to take hours of clicking through the Purview portal now happens in a single conversation.*

---

## Overview

The **Microsoft Purview MCP Server** is a next-generation [Model Context Protocol](https://modelcontextprotocol.io/) server that connects **Microsoft Purview's compliance engine** directly to **AI agents like Claude and Copilot Studio**. It transforms complex audit, retention, and governance workflows into simple, conversational commands — eliminating portal-hopping, manual exports, and repetitive admin tasks.

---

## Key Features

### 🔍 Copilot Interaction Auditing
Automatically search, retrieve, and analyze audit logs for every Copilot interaction across your Microsoft 365 tenant. Full visibility into who's using Copilot, what they're prompting, and when.

### 📊 HTML Dashboard Generation
Generate branded, executive-ready compliance dashboards from raw audit data — instantly — and publish them directly to SharePoint.

### 📤 SharePoint Auto-Publish
Reports are automatically uploaded to your designated SharePoint document library — no manual downloads, no portal clicks, no human intervention.

### 🏷️ Retention Label Management
Create, assign, and manage Purview retention labels programmatically via PowerShell. Enforce data governance policies at scale without touching the compliance portal.

### ⏰ Scheduled Daily Automation
Set it and forget it. Daily audit sweeps run on schedule, delivering fresh compliance reports to SharePoint and email every morning.

### 📦 Audit Export
Run compliance searches and export results to structured formats automatically — no waiting around in the Purview portal.

---

## Architecture

```
User → Claude / Copilot Studio Agent
            ↓
     Purview MCP Server (POST /mcp)
            ↓
     Microsoft Purview Audit Search API
            ↓
     Structured Results → HTML Dashboard → SharePoint Upload
            ↓
       📊 Done. Report is live.
```

| Component | Detail |
|---|---|
| **Transport** | Streamable HTTP (`POST /mcp`) |
| **Mode** | Stateless — horizontally scalable, zero session overhead |
| **Auth** | Azure AD App Registration with least-privilege Microsoft Graph permissions |
| **Write Operations** | Microsoft Graph API (fully compatible with app-only tokens) |
| **Deployment** | Azure App Service, Azure Functions, or any Node.js host |
| **AI Clients** | Claude (claude.ai / API), Copilot Studio (`x-ms-agentic-protocol: mcp-streamable-1.0`) |

---

## Getting Started

### Prerequisites

- Node.js 18+
- Azure AD App Registration with the following Microsoft Graph permissions:
  - `AuditLog.Read.All`
  - `Sites.ReadWrite.All`
  - `Mail.Send` (optional, for email reports)
- Access to Microsoft Purview in your M365 tenant

### Installation

```bash
git clone https://github.com/YOUR_USERNAME/purview-mcp-server.git
cd purview-mcp-server
npm install
```

### Configuration

Create a `.env` file in the project root:

```env
AZURE_TENANT_ID=your-tenant-id
AZURE_CLIENT_ID=your-client-id
AZURE_CLIENT_SECRET=your-client-secret
SHAREPOINT_SITE_URL=https://yourtenant.sharepoint.com/sites/yoursite
SHAREPOINT_LIBRARY=Documents/Copilot Reports
```

### Run

```bash
npm start
```

The server starts on `http://localhost:3000/mcp`.

### Connect to Claude

Use this server as an MCP endpoint in Claude Desktop, Claude.ai, or via the Anthropic API:

```json
{
  "type": "url",
  "url": "https://your-deployed-url.azurewebsites.net/mcp",
  "name": "purview-mcp"
}
```

### Connect to Copilot Studio

Add the server as a custom MCP action in Copilot Studio using the Streamable HTTP protocol:

```
URL: https://your-deployed-url.azurewebsites.net/mcp
Header: x-ms-agentic-protocol: mcp-streamable-1.0
```

---

## Security

- **Zero Trust Architecture** — Every request is authenticated and every permission is scoped to least-privilege
- **No Secrets in Code** — Uses Azure Key Vault or environment variable injection
- **App-Only Token Compatible** — All write operations use Microsoft Graph API, avoiding SharePoint REST API token limitations
- **Enterprise-Grade** — Built by an engineer with TS/SCI clearance and 10+ years of enterprise IT & cybersecurity experience

---

## Use Cases

| Persona | Problem | Solution |
|---|---|---|
| **M365 Admin** | Hours spent in the Purview portal running audit searches | One-sentence prompt → full audit report in seconds |
| **Security Engineer** | No visibility into Copilot usage across the tenant | Automated daily Copilot interaction logs with dashboards |
| **Compliance Officer** | Manual retention label assignment across sites | Programmatic label management at scale |
| **IT Leader** | Can't prove Copilot ROI to leadership | Executive-ready usage dashboards auto-published to SharePoint |

---

## Tech Stack

`Node.js` · `TypeScript` · `MCP SDK` · `Microsoft Graph API` · `Microsoft Purview APIs` · `PowerShell` · `Azure App Service`

---

## Related Projects

This server is part of the **Microsoft Services MCP Servers** collection:

- 📂 **SharePoint MCP Server** — 150+ tools for site management, branding, and document ops
- 🔒 **Power Platform Security MCP Server** — Vulnerability scanning and security posture
- 📄 **PDF-to-Excel MCP Server** — Document processing with SharePoint integration

---

## Author

**Kerolos** — Senior Infrastructure & Security Engineer

10+ years of enterprise IT & cybersecurity | TS/SCI Cleared | CCNA · CCNA Security · CCNA Cyber Ops · MCSE · MCSA

🌐 Blog: [Power of Automation](https://powerofautomation2025.blogspot.com)

---

## License

This project is licensed under the MIT License. See [LICENSE](LICENSE) for details.

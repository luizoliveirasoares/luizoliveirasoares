# Sistema operacional dos logins no Microsoft 365

Descubra se os usuários estão entrando no M365 a partir de **Windows, Linux ou macOS**
(e também iOS, Android e ChromeOS).

A informação vem dos **logs de entrada do Microsoft Entra ID** (campo
`deviceDetail.operatingSystem`), que registram cada login em Outlook, Teams,
SharePoint, OneDrive, portal do Office e demais apps.

## Pré-requisitos

- PowerShell 7+ (ou Windows PowerShell 5.1)
- Módulo Microsoft Graph:
  ```powershell
  Install-Module Microsoft.Graph -Scope CurrentUser
  ```
- Conta com a função **Leitor de Relatórios**, **Leitor de Segurança** ou **Administrador Global**
- Permissões Graph: `AuditLog.Read.All` e `Directory.Read.All` (solicitadas no login)
- **Licença Microsoft Entra ID P1 ou P2** (inclusa no Microsoft 365 Business Premium, E3 e E5).
  Sem ela, a API de logs de entrada não fica disponível — veja a alternativa pelo portal abaixo.

## Uso

```powershell
# Últimos 7 dias, todos os usuários
.\Get-M365LoginOS.ps1

# Últimos 30 dias, só logins bem-sucedidos
.\Get-M365LoginOS.ps1 -Days 30 -OnlySuccess

# Um usuário específico
.\Get-M365LoginOS.ps1 -Days 14 -UserPrincipalName joao@empresa.com.br
```

### Arquivos gerados

| Arquivo | Conteúdo |
|---|---|
| `m365-login-os-resumo.csv` | Total de logins e de usuários por sistema operacional |
| `m365-login-os-por-usuario.csv` | Cada usuário × SO usado, quantidade de logins, dispositivos e último login |
| `m365-login-os-detalhado.csv` | Um registro por login (data, SO, navegador, app, IP, cidade, se o dispositivo é gerenciado/conforme) |

Exemplo de saída no console:

```
SistemaOperacional QtdLogins QtdUsuarios
------------------ --------- -----------
Windows                 4210          87
macOS                    612          14
iOS                      530          40
Android                  301          22
Linux                     45           3
```

## Alternativa sem script (portal)

1. Acesse **entra.microsoft.com** → **Identidade** → **Monitoramento e integridade** → **Logs de entrada**
2. Clique em **Adicionar filtros** → **Sistema operacional** e escolha Windows, Linux ou MacOs
3. Use **Baixar** para exportar em CSV

## Consulta KQL (se os logs são enviados ao Log Analytics / Sentinel)

```kusto
SigninLogs
| where TimeGenerated > ago(30d)
| extend OS = tostring(DeviceDetail.operatingSystem)
| extend Familia = case(
    OS startswith "Windows", "Windows",
    OS has_any ("MacOs", "Mac OS", "OS X"), "macOS",
    OS has "Linux", "Linux",
    OS has "Ios", "iOS",
    OS has "Android", "Android",
    "Outro")
| summarize Logins = count(), Usuarios = dcount(UserPrincipalName) by Familia
| order by Logins desc
```

## Observações

- O SO é detectado pelo **user-agent** do cliente; em logins pelo navegador ele pode
  ser alterado pelo usuário, então trate como informação indicativa, não prova.
- Para uma visão confiável de **máquinas corporativas**, cruze com os dispositivos
  registrados/gerenciados (Entra ID → Dispositivos, ou Intune). As colunas `Gerenciado`,
  `Conforme` e `TipoRegistro` do relatório detalhado ajudam nisso.

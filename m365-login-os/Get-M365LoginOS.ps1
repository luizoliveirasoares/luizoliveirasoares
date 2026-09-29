<#
.SYNOPSIS
    Relatorio de sistema operacional (Windows, Linux, macOS, etc.) usado pelos
    usuarios ao fazer login no Microsoft 365.

.DESCRIPTION
    Le os logs de entrada (sign-in logs) do Microsoft Entra ID via Microsoft Graph
    e classifica cada login pelo sistema operacional informado em deviceDetail.
    Gera tres arquivos CSV:
      - <prefixo>-detalhado.csv : um registro por login
      - <prefixo>-por-usuario.csv : usuario x sistema operacional (qtd e ultimo login)
      - <prefixo>-resumo.csv : total de logins e usuarios por sistema operacional

    Requisitos:
      - Modulo Microsoft.Graph.Reports e Microsoft.Graph.Authentication
        (Install-Module Microsoft.Graph -Scope CurrentUser)
      - Permissoes: AuditLog.Read.All e Directory.Read.All
      - Licenca Microsoft Entra ID P1 ou P2 no tenant (exigida pela API de sign-in logs)
      - Os logs ficam disponiveis por 30 dias (P1/P2).

.PARAMETER Days
    Quantos dias para tras consultar (1 a 30). Padrao: 7.

.PARAMETER UserPrincipalName
    Opcional. Filtra por um usuario especifico (ex.: joao@empresa.com.br).

.PARAMETER OnlySuccess
    Considera apenas logins bem-sucedidos.

.PARAMETER OutputPrefix
    Prefixo dos arquivos CSV gerados. Padrao: .\m365-login-os

.EXAMPLE
    .\Get-M365LoginOS.ps1 -Days 30 -OnlySuccess

.EXAMPLE
    .\Get-M365LoginOS.ps1 -Days 7 -UserPrincipalName joao@empresa.com.br
#>
[CmdletBinding()]
param(
    [ValidateRange(1, 30)]
    [int]$Days = 7,

    [string]$UserPrincipalName,

    [switch]$OnlySuccess,

    [string]$OutputPrefix = ".\m365-login-os"
)

$ErrorActionPreference = 'Stop'

function Get-OSFamily {
    param([string]$OperatingSystem)

    if ([string]::IsNullOrWhiteSpace($OperatingSystem)) { return 'Desconhecido' }

    switch -Regex ($OperatingSystem) {
        '^Windows'           { return 'Windows' }
        'Mac ?OS|OS ?X|Mac'  { return 'macOS' }
        'Linux|Ubuntu|Fedora|Debian|Red ?Hat|CentOS|SUSE' { return 'Linux' }
        'ChromeOS|Chrome OS' { return 'ChromeOS' }
        'iOS|iPadOS|iPhone|iPad' { return 'iOS' }
        'Android'            { return 'Android' }
        default              { return "Outro ($OperatingSystem)" }
    }
}

foreach ($module in 'Microsoft.Graph.Authentication', 'Microsoft.Graph.Reports') {
    if (-not (Get-Module -ListAvailable -Name $module)) {
        throw "Modulo '$module' nao encontrado. Instale com: Install-Module Microsoft.Graph -Scope CurrentUser"
    }
}
Import-Module Microsoft.Graph.Authentication, Microsoft.Graph.Reports

if (-not (Get-MgContext)) {
    Connect-MgGraph -Scopes 'AuditLog.Read.All', 'Directory.Read.All' -NoWelcome
}

$since = (Get-Date).ToUniversalTime().AddDays(-$Days).ToString('yyyy-MM-ddTHH:mm:ssZ')
$filters = @("createdDateTime ge $since")
if ($UserPrincipalName) { $filters += "userPrincipalName eq '$UserPrincipalName'" }
if ($OnlySuccess)       { $filters += "status/errorCode eq 0" }
$filter = $filters -join ' and '

Write-Host "Consultando logs de entrada desde $since ..." -ForegroundColor Cyan
$signIns = Get-MgAuditLogSignIn -Filter $filter -All -PageSize 999
Write-Host "Logins encontrados: $($signIns.Count)" -ForegroundColor Cyan

if (-not $signIns) {
    Write-Warning 'Nenhum login encontrado para o periodo/filtro informado.'
    return
}

$detailed = foreach ($s in $signIns) {
    $os = $s.DeviceDetail.OperatingSystem
    [pscustomobject]@{
        DataHoraUTC       = $s.CreatedDateTime
        Usuario           = $s.UserDisplayName
        UPN               = $s.UserPrincipalName
        SistemaOperacional = Get-OSFamily $os
        SO_Original       = $os
        Navegador         = $s.DeviceDetail.Browser
        Dispositivo       = $s.DeviceDetail.DisplayName
        DeviceId          = $s.DeviceDetail.DeviceId
        Gerenciado        = $s.DeviceDetail.IsManaged
        Conforme          = $s.DeviceDetail.IsCompliant
        TipoRegistro      = $s.DeviceDetail.TrustType
        Aplicativo        = $s.AppDisplayName
        AppCliente        = $s.ClientAppUsed
        IP                = $s.IPAddress
        Cidade            = $s.Location.City
        Pais              = $s.Location.CountryOrRegion
        Sucesso           = ($s.Status.ErrorCode -eq 0)
        CodigoErro        = $s.Status.ErrorCode
    }
}

$byUser = $detailed |
    Group-Object UPN, SistemaOperacional |
    ForEach-Object {
        $first = $_.Group[0]
        [pscustomobject]@{
            Usuario            = $first.Usuario
            UPN                = $first.UPN
            SistemaOperacional = $first.SistemaOperacional
            QtdLogins          = $_.Count
            Dispositivos       = (($_.Group.Dispositivo | Where-Object { $_ } | Sort-Object -Unique) -join '; ')
            UltimoLoginUTC     = ($_.Group.DataHoraUTC | Sort-Object -Descending | Select-Object -First 1)
        }
    } |
    Sort-Object UPN, SistemaOperacional

$summary = $detailed |
    Group-Object SistemaOperacional |
    ForEach-Object {
        [pscustomobject]@{
            SistemaOperacional = $_.Name
            QtdLogins          = $_.Count
            QtdUsuarios        = ($_.Group.UPN | Sort-Object -Unique).Count
        }
    } |
    Sort-Object QtdLogins -Descending

$detailed | Export-Csv "$OutputPrefix-detalhado.csv"   -NoTypeInformation -Encoding UTF8
$byUser   | Export-Csv "$OutputPrefix-por-usuario.csv" -NoTypeInformation -Encoding UTF8
$summary  | Export-Csv "$OutputPrefix-resumo.csv"      -NoTypeInformation -Encoding UTF8

Write-Host "`nResumo por sistema operacional:" -ForegroundColor Green
$summary | Format-Table -AutoSize

Write-Host "Arquivos gerados:" -ForegroundColor Green
Write-Host "  $OutputPrefix-detalhado.csv"
Write-Host "  $OutputPrefix-por-usuario.csv"
Write-Host "  $OutputPrefix-resumo.csv"

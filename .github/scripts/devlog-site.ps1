# Compara duas versões do index.html e posta no #devlog do Discord que o
# site foi atualizado, com o que mudou no roadmap. Roda no GitHub (pwsh) e
# no Windows PowerShell 5.1.
#
# Uso:
#   devlog-site.ps1 -Antes antes.html -Depois depois.html [-Teste] [-SoMostrar]
# A URL do webhook vem de -Webhook ou da variável DISCORD_WEBHOOK.

param(
    [Parameter(Mandatory)] [string] $Antes,
    [Parameter(Mandatory)] [string] $Depois,
    [string] $Webhook,
    [switch] $Teste,      # marca a mensagem como teste
    [switch] $SoMostrar   # só mostra o JSON, não posta
)

$ErrorActionPreference = 'Stop'
$utf8 = New-Object System.Text.UTF8Encoding $false
$site = 'https://kleosgame.github.io/'

function Limpar([string] $html) {
    $texto = [regex]::Replace($html, '<[^>]+>', '')
    $texto = [System.Net.WebUtility]::HtmlDecode($texto)
    return ([regex]::Replace($texto, '\s+', ' ')).Trim()
}

function Cortar([string] $texto, [int] $max) {
    if ($texto.Length -le $max) { return $texto }
    return $texto.Substring(0, $max - 1) + '…'
}

# Lê os passos do roadmap: estado (done, now, next, more), título e texto.
function Ler-Roadmap([string] $caminho) {
    $passos = [ordered]@{}
    if (-not (Test-Path $caminho)) { return $passos }
    $html = [System.IO.File]::ReadAllText((Resolve-Path $caminho), $utf8)
    $padrao = '<li class="(\w+)">(.*?)</li>'
    foreach ($m in [regex]::Matches($html, $padrao, 'Singleline')) {
        $corpo = $m.Groups[2].Value
        if ($corpo -notmatch '<h3>(.*?)</h3>') { continue }
        $titulo = Limpar $Matches[1]
        $texto = if ($corpo -match '(?s)<p>(.*?)</p>') { Limpar $Matches[1] } else { '' }
        $passos[$titulo] = [pscustomobject]@{ Estado = $m.Groups[1].Value; Texto = $texto }
    }
    return $passos
}

$roadmapAntes = Ler-Roadmap $Antes
$roadmapDepois = Ler-Roadmap $Depois

$linhas = @()
foreach ($titulo in $roadmapDepois.Keys) {
    $agora = $roadmapDepois[$titulo]
    $passoAntes = $roadmapAntes[$titulo]
    if ($passoAntes -and $passoAntes.Estado -eq $agora.Estado -and $passoAntes.Texto -eq $agora.Texto) { continue }

    $mudouEstado = -not $passoAntes -or $passoAntes.Estado -ne $agora.Estado
    $rotulo = switch ($agora.Estado) {
        'done' { if ($mudouEstado) { '✅ Concluído' } else { '✅ Atualizado' } }
        'now'  { if ($mudouEstado) { '▶️ Começou' } else { '▶️ Em andamento' } }
        default { if ($passoAntes) { '🗺️ Atualizado' } else { '🆕 Novo no roadmap' } }
    }
    $linhas += "**$rotulo · $titulo**`n$(Cortar $agora.Texto 700)"
}

$descricao = if ($linhas.Count -gt 0) {
    "O que mudou no roadmap:`n`n" + ($linhas -join "`n`n")
} else {
    'O site recebeu ajustes, sem mudanças no roadmap.'
}

$prefixo = if ($Teste) { '🧪 [TESTE] ' } else { '' }
$corpo = @{
    embeds = @(@{
        title       = $prefixo + '🌐 Site atualizado'
        url         = $site
        description = Cortar $descricao 4000
        color       = 0xe0a458
        footer      = @{ text = 'kleosgame.github.io' }
    })
    allowed_mentions = @{ parse = @() }
} | ConvertTo-Json -Depth 6

if ($SoMostrar) { Write-Host $corpo; exit 0 }
if (-not $Webhook) { $Webhook = $env:DISCORD_WEBHOOK }
if (-not $Webhook) { throw 'Sem a URL do webhook (DISCORD_WEBHOOK).' }
Invoke-RestMethod -Method Post -Uri $Webhook -ContentType 'application/json; charset=utf-8' -Body $utf8.GetBytes($corpo) | Out-Null
Write-Host 'Postado no Discord.'

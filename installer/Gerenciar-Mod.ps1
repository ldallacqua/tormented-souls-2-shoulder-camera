param(
    [ValidateSet('Instalar','Ativar','Desativar')][string]$Acao='Instalar',
    [string]$Pasta='',
    [switch]$ValidateOnly
)
$ErrorActionPreference='Stop'
if (-not $Pasta) { $Pasta=Read-Host 'Pasta TormentedSouls2\Binaries\Win64 do jogo' }
$target=[IO.Path]::GetFullPath($Pasta).TrimEnd('\')
$sourceRoot=[IO.Path]::GetFullPath($PSScriptRoot).TrimEnd('\')
$exe=Join-Path $target 'TormentedSouls2-Win64-Shipping.exe'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) { throw 'Executavel do jogo nao encontrado.' }
$runtime=Join-Path $target 'ue4ss'
$marker=Join-Path $runtime 'TormentedShoulderCamera-install.json'
$mods=Join-Path $runtime 'Mods\mods.txt'
$state=$null
if (Test-Path -LiteralPath $marker) {
    $state=Get-Content -LiteralPath $marker -Raw | ConvertFrom-Json
    if ($state.mod -ne 'TormentedShoulderCamera') { throw 'Marcador de instalacao inesperado.' }
}
if (-not $ValidateOnly -and (Get-Process -Name 'TormentedSouls2-Win64-Shipping' -ErrorAction SilentlyContinue)) {
    throw 'Feche o jogo antes de instalar, ativar ou desativar. Durante a partida, F6 alterna o mod.'
}
if ($Acao -ne 'Instalar') {
    if (-not $state) { throw 'Instalacao deste mod nao identificada.' }
    $text=Get-Content -LiteralPath $mods -Raw
    if ($text -notmatch '(?m)^TormentedShoulderCamera[ \t]*:') { throw 'Entrada do mod nao encontrada.' }
    $value=if ($Acao -eq 'Ativar') { '1' } else { '0' }
    $text=$text -replace '(?m)^TormentedShoulderCamera[ \t]*:[ \t]*[01][ \t]*\r?$',"TormentedShoulderCamera : $value"
    if (-not $ValidateOnly) { [IO.File]::WriteAllText($mods,$text,[Text.Encoding]::ASCII) }
    Write-Output "$Acao validado."
    exit
}
$manifest=Get-Content -LiteralPath (Join-Path $sourceRoot 'manifest.json') -Raw | ConvertFrom-Json
if ((Get-FileHash -LiteralPath $exe -Algorithm SHA256).Hash.ToLowerInvariant() -ne $manifest.game_exe_sha256) {
    throw 'Executavel diferente da versao testada. Revise a compatibilidade antes de instalar.'
}
if ((Test-Path -LiteralPath $runtime) -and -not $state) {
    throw 'Outra instalacao de UE4SS foi encontrada. Consulte a instalacao manual no README.'
}
$files=@()
foreach ($item in $manifest.files.PSObject.Properties) {
    $relative=$item.Name
    if (-not $relative.StartsWith('Win64/')) { throw 'Caminho inesperado no manifesto.' }
    $source=[IO.Path]::GetFullPath((Join-Path $sourceRoot $relative))
    $dest=[IO.Path]::GetFullPath((Join-Path $target $relative.Substring(6)))
    if (-not $source.StartsWith($sourceRoot+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Origem invalida.' }
    if (-not $dest.StartsWith($target+'\',[StringComparison]::OrdinalIgnoreCase)) { throw 'Destino invalido.' }
    if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -ne $item.Value) {
        throw "Arquivo do pacote alterado: $relative"
    }
    $skip=$false
    if (Test-Path -LiteralPath $dest) {
        $current=(Get-FileHash -LiteralPath $dest -Algorithm SHA256).Hash.ToLowerInvariant()
        $skip=$current -eq $item.Value
        # Preserve user configuration and other mods during an owned upgrade.
        if ($state -and ($relative -eq 'Win64/ue4ss/UE4SS-settings.ini' -or $relative -eq 'Win64/ue4ss/Mods/mods.txt' -or $relative -like '*/Scripts/config.lua')) { $skip=$true }
        if (-not $skip) {
            $old=if ($state) { $state.files.PSObject.Properties[$relative] } else { $null }
            if (-not $old -or $current -ne $old.Value) { throw "Conflito com arquivo local: $dest" }
        }
    }
    $files += [pscustomobject]@{Source=$source;Destination=$dest;Skip=$skip}
}
if ($ValidateOnly) { Write-Output "Validado: $($files.Count) arquivos; nenhuma alteracao aplicada.";exit }
foreach ($file in $files) {
    if (-not $file.Skip) {
        $parent=Split-Path -Parent $file.Destination
        if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Copy-Item -LiteralPath $file.Source -Destination $file.Destination -Force
    }
}
Copy-Item -LiteralPath (Join-Path $sourceRoot 'manifest.json') -Destination $marker -Force
Write-Output 'Mod instalado. Abra o jogo normalmente.'

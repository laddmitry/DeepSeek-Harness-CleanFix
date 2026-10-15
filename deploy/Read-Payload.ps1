function Get-HarnessPayload {
    param([Parameter(Mandatory)][string]$RepositoryRoot,[Parameter(Mandatory)][string]$Name,[Parameter(Mandatory)][string]$Destination)
    $root=[IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\')
    $manifest=Get-Content -LiteralPath (Join-Path $root 'payload\manifest.json') -Raw|ConvertFrom-Json
    $assets=@($manifest.assets|Where-Object name -eq $Name)
    if($assets.Count -ne 1){throw "Unknown or repeated payload: $Name"}
    $asset=$assets[0]
    if(Test-Path -LiteralPath $Destination){
        if((Get-FileHash -LiteralPath $Destination).Hash.ToLowerInvariant() -eq $asset.SHA256){return $asset}
        throw "Existing payload has a different hash: $Destination"
    }
    $output=[IO.File]::Open($Destination,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    try {
        foreach($part in $asset.parts){
            $path=[IO.Path]::GetFullPath((Join-Path $root $part.path))
            if(!$path.StartsWith($root+'\',[StringComparison]::OrdinalIgnoreCase)){throw 'Payload part escapes repository'}
            $item=Get-Item -LiteralPath $path -Force
            if($item.PSIsContainer -or ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)){throw 'Payload part must be an ordinary file'}
            if($item.Length -ne $part.bytes -or (Get-FileHash -LiteralPath $path).Hash.ToLowerInvariant() -ne $part.SHA256){throw "Payload part hash mismatch: $($part.path)"}
            $partStream=[IO.File]::OpenRead($path)
            try{$partStream.CopyTo($output)}finally{$partStream.Dispose()}
        }
    } finally {$output.Dispose()}
    if((Get-Item -LiteralPath $Destination).Length -ne $asset.bytes -or (Get-FileHash -LiteralPath $Destination).Hash.ToLowerInvariant() -ne $asset.SHA256){throw "Assembled payload hash mismatch: $Name"}
    return $asset
}

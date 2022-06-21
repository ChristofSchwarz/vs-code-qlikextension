git add . 
git commit -m "updates"  
git push -u origin main
$confirmation = Read-Host "Increase the version counter in .qext file now? (y/n)"
if ($confirmation -like 'y*') {
    $qextFilename = Get-ChildItem -Filter '*.qext' | Select-Object -First 1
    $qext = Get-Content $qextFilename -raw | ConvertFrom-Json
    $version = $qext.version.split(".")[2]
    [int]$versionNo = 0
    [bool]$result = [int]::TryParse($version, [ref]$versionNo)
    if ($result) {
        $versionNo = $versionNo + 1
        $versionNoStr = "{0:d$($version.length)}" -f $versionNo
        $versionNoStr = ( -join ($qext.version.split(".")[0], ".", $qext.version.split(".")[1], ".", $versionNoStr))
        Write-Host "increased version number to $($versionNoStr) in $($qextFilename)"
        $qext.version = $versionNoStr
        $qext | ConvertTo-Json -depth 100 | Out-File $qextFilename -Encoding Utf8
    }
    else {
        Write-Host "Cannot increase the version number, it isn't an integer"
    }
}

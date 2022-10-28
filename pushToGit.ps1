# Version 28-Oct-2022
# check here https://raw.githubusercontent.com/ChristofSchwarz/vs-code-qlikextension/main/pushToGit.ps1

# read info from .git\config file

if (Test-Path -Path ".git\config" -PathType Leaf) {
    $branch = $null
    $url = $null
    foreach ($line in [System.IO.File]::ReadLines(".git\config")) {
        if ($line -like "*branch *") {
            $branch = $line.Split('"')[1]
        }
        if ($line -like "*url*=*") {
            $url = $line.Split('=')[1].Trim()
        }
    }
    Write-Host -f Cyan "Branch '$branch' of git $url"
    $comment = Read-Host "(Optional) Please enter comment for this commit"
    if (!$comment) { $comment = 'updates' }

    git add . 
    git commit -m $comment  
    git push -u origin $branch
    $qextFilename = Get-ChildItem -Filter '*.qext' | Select-Object -First 1
    if ($qextFilename) {
        $qext = Get-Content $qextFilename -raw | ConvertFrom-Json
        if ($qext.homepage -like '*github.com*') {
            Write-Host -f Cyan "Maybe create a release $($qext.version) on $($qext.homepage)/releases/new"
        }
        if ($qext.repository -like '*github.com*') {
            Write-Host -f Cyan "Maybe create a release $($qext.version) on $($qext.repository)/releases/new"
        }
        else {
            Write-Host "Pushed release $($qext.version) to git"
        }
        $confirmation = Read-Host "Increase the version counter in .qext file now? (y/n)"
        if ($confirmation -like 'y*') {
            $version = $qext.version.split(".")[2]
            [int]$versionNo = 0
            [bool]$result = [int]::TryParse($version, [ref]$versionNo)
            if ($result) {
                $versionNo = $versionNo + 1
                $versionNoStr = "{0:d$($version.length)}" -f $versionNo
                $versionNoStr = ( -join ($qext.version.split(".")[0], ".", $qext.version.split(".")[1], ".", $versionNoStr))
                Write-Host "Increased version number to $($versionNoStr) in $($qextFilename)"
                $qext.version = $versionNoStr
                $qext | ConvertTo-Json -depth 100 | Out-File $qextFilename -Encoding Utf8
            }
            else {
                Write-Host "Cannot increase the version number, it isn't an integer"
            }
        }
    }
    else {
        Write-Host -f Yellow "No .qext file in this folder."
    }
} 
else {
    Write-Host -f Red "This folder is not part of a git."

}

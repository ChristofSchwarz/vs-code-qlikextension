# Script will upload the extension (that is the parent path to this .ps1 script)
# to Qlik Sense Windows or Qlik Cloud or both, depending on the settings in settings.json
# if the extension already exists, it will be patched with the new version

# Christof Schwarz, 06-Jun-2022
Write-Host "*** updateExtension PowerShell Script by Christof Schwarz ***"

# Read settings from Json file
$settings = Get-Content -Raw -Path ".vscode\settings.json" | ConvertFrom-Json

$qlik_exe = $settings.christofs_options.qlik_cli_location 
# Write-Host $qlik_exe

# Figure out the name of the extension by the .qext file
$folder = (Split-Path $PSScriptRoot -Parent)
if ((Get-ChildItem -Path $folder -filter *.qext | Measure-Object).Count -ne 1) {
    Write-Host "The extension folder does not have ONE .qext file" -ForegroundColor 'red' -BackgroundColor 'black'
    Exit
}
$extension_name = (Get-ChildItem "$($folder)\*.qext" | Select-Object BaseName).BaseName
# Write-Host "Extension is $($extension_name)"

# Make a temp copy of this work folder but remove the .ps1 file (Qlik Cloud wont
# allow a .ps1 file to be part of an extension .zip)
$rnd = Get-Random
Copy-Item "$($folder)" -Destination "$($folder)$($rnd)" -Recurse -Container
Remove-Item -LiteralPath "$($folder)$($rnd)\.vscode" -Force -Recurse
Remove-Item -LiteralPath "$($folder)$($rnd)\doc" -Force -Recurse
Remove-Item -LiteralPath "$($folder)$($rnd)\.git" -Force -Recurse
Remove-Item -LiteralPath "$($folder)$($rnd)\pushToGit.bat" -Force
Write-Host "Creating zip file from folder '$($folder)'"

# create a zip file from the temp folder then remove the temp folder 
$file = "$($folder)_upload.zip"
if (Test-Path $file) {
    Remove-Item $file
}
Compress-Archive -Path "$($folder)$($rnd)" -DestinationPath "$file"
Remove-Item -LiteralPath "$($folder)$($rnd)" -Force -Recurse

# ------------------- Qlik Sense Windows ------------------------

if (@("win", "both").Contains($settings.christofs_options.save_to)) {
    # want to upload to Qlik Sense on Windows
    Write-Host "--> Qlik Sense on Windows: Publishing extension '$($extension_name)'"
    $cert = Get-PfxCertificate -FilePath $settings.christofs_options.client_cert_location
    $api_url = $settings.christofs_options.qrs_url
    $xrfkey = "A3VWMWM3VGRH4X3F"
    $headers = @{
        "$($settings.christofs_options.header_key)" = $settings.christofs_options.header_value; 
        "X-Qlik-Xrfkey"                             = $xrfkey
    }
    
    
    $extension_list = Invoke-RestMethod "$($api_url)/extension?filter=name eq '$($extension_name)'&xrfkey=$($xrfkey)" `
        -Headers $headers `
        -Certificate $cert -SkipCertificateCheck `
    | ConvertTo-Json
    
    $extension_list = $extension_list | ConvertFrom-Json
    
    if ($extension_list.length -eq 0) {
        Write-Host "Extension '$($extension_name)' does not exist. Uploading it first time ...'" 
        $gotoupload = 1
    }
    elseif ($extension_list.length -eq 1) {
        $extension_id = $extension_list[0].id
        Write-Host "Removing existing extension '$($extension_name)' ($($extension_id)) ..." 
        Invoke-RestMethod -method 'DELETE' "$($api_url)/extension/$($extension_id)?xrfkey=$($xrfkey)" `
            -Headers $headers `
            -Certificate $cert -SkipCertificateCheck
        $gotoupload = 1
    }
    else {
        Write-Host "Error: The name '$($extension_name)' exists $($extension_list.value.length) times."
        $gotoupload = 0
    }
    
    if ($gotoupload -eq 1) {
        $new_ext = Invoke-RestMethod -method 'POST' "$($api_url)/extension/upload?xrfkey=$($xrfkey)" `
            -Headers $headers `
            -Certificate $cert -SkipCertificateCheck `
            -inFile $file `
        | ConvertTo-Json -Depth 4
        # Remove-Item $file
        $new_ext = $new_ext | ConvertFrom-Json
        Write-Host "Extension '$($extension_name)' uploaded ($($new_ext[0].id))"
    }
}

# ------------------- Qlik Cloud ----------------------

if (@("cloud", "both").Contains($settings.christofs_options.save_to)) {
    # want to upload to Qlik Cloud

    $resp = & $qlik_exe context use "$($settings.christofs_options.qlik_cli_context)" 
    # if the response is an Error (length: 0), that is when the context doesn't exist, skip the rest.
    if ($resp.length -gt 0) {
    
        Write-Host "--> Qlik Cloud: Publishing extension '$($extension_name)'"
        # $extension_exists = & $qlik_exe extension get "$($extension_name)"
        $extension_list = & $qlik_exe extension ls
        $extension_list = $extension_list | ConvertFrom-Json

        # parse through the response Json list of extensions and look for the given one
        $extension_id = ""

        foreach ($extension in $extension_list) {
            # Write-Host "is it $($extension.qextFilename) ?"
            if ($extension.qextFilename -like "$($extension_name)") {
                $extension_id = $extension.id
                Write-Host "Patching existing extension '$($extension_name)' (id $($extension_id))"
            } 
        }

        if ($extension_id -eq "") {
            Write-Host "Uploading extension '$($extension_name)' first time ..."
            $resp = & $qlik_exe extension create "$($extension_id)" --file "$($file)"
        }
        else {
            $resp = & $qlik_exe extension patch "$($extension_id)" --file "$($file)"
        }
    
        if ($resp.Length -gt 0) {
            $resp = $resp | ConvertFrom-Json
            Write-Host "Extension '$($extension_name)' uploaded (id $($resp.id))"
        }
        else {
            Write-Host "An error occurred. Not getting expected response." -ForegroundColor 'red' -BackgroundColor 'black'
        }
    }
} 

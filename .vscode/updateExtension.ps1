# Script will upload the extension (that is the parent path to this .ps1 script)
# to Qlik Sense Windows or Qlik Cloud or both, depending on the settings in settings.json
# if the extension already exists, it will be patched with the new version

# Christof Schwarz, 06-Jun-2022, Original version
# Christof Schwarz, 21-Jun-2022, fix to check if .bat file or .git folder exists before deleting it
# Christof Schwarz, 15-Jul-2022, delete all *.ps1 files in the zip copy
# Christof Schwarz, 25-Sep-2022, ask to enter new API Key in cloud, when first command fails 

Write-Host "*** update Qlik Extension PS Script by Christof Schwarz v1.1 ***"

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
# allow a .ps1 or .bat file to be part of an extension .zip)
$rnd = Get-Random
Copy-Item "$($folder)" -Destination "$($folder)$($rnd)" -Recurse -Container
Remove-Item -LiteralPath "$($folder)$($rnd)\.vscode" -Force -Recurse
if (Test-Path -Path "$($folder)$($rnd)\doc") {
    Remove-Item -LiteralPath "$($folder)$($rnd)\doc" -Force -Recurse
}
if (Test-Path -Path "$($folder)$($rnd)\.git") {
    Remove-Item -LiteralPath "$($folder)$($rnd)\.git" -Force -Recurse
}
if (Test-Path "$($folder)$($rnd)\*.ps1" -PathType leaf) {
    Remove-Item "$($folder)$($rnd)\*.ps1" -Force
}
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
    Write-Host "`n--> Qlik Sense on Windows: Publishing extension '$($extension_name)'"
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
    
        Write-Host -f Cyan "`n--> Qlik Cloud: Publishing extension '$($extension_name)' to '$($settings.christofs_options.qlik_cli_context)'"
        # $extension_exists = & $qlik_exe extension get "$($extension_name)"
        $extension_list = & $qlik_exe extension ls
        if (-not $extension_list) {
            Write-Host -f Red "Error: qlik.exe does not answer as expected."
            $server = & $qlik_exe context get | Where-Object { $_ -like "Server:*" }
            $server = ($server.split('Server:')[1]).Trim()
            $context = & $qlik_exe context get | Where-Object { $_ -like "Name:*" }
            $context = ($context.split('Name:')[1]).Trim()
            Write-Host -F Green "Try context $context with a new API Key, get it on $server"
            
            $apikey = Read-Host -Prompt "New API Key (leave emtpy to quit)"
            if (-not $apikey) { Exit }
            $info = & $qlik_exe context update "$context" --api-key $apikey
            # Write-Host -F Green (ConvertTo-Json -i $info)
            $extension_list = & $qlik_exe extension ls
            if (-not $extension_list) {
                Write-Host -f Red "Error: qlik.exe still does not answer as expected."
                Write-Host -f Red "Please get qlik.exe work with the context $context"
            }
        }
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

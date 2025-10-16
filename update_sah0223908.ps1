Remove-Item -Path "C:\Users\rkitch01\code\run_app_SAH0223908\Modules" -Recurse -Force
Copy-Item -Path "$HOME\code\app_management\app_management\Modules" `
    -Destination "C:\Users\rkitch01\code\run_app_SAH0223908" `
    -Recurse

Copy-Item -Path "$HOME\code\app_management\app_management\run_apps_tab_html.ps1" `
    -Destination "C:\Users\rkitch01\code\run_app_SAH0223908" `
    -Force

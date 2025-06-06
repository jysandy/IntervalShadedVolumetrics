Remove-Item .\vendor\ -Recurse -Force -ErrorAction Ignore
mkdir vendor
Invoke-WebRequest "https://github.com/GPUOpen-LibrariesAndSDKs/FidelityFX-SDK/archive/refs/tags/v1.1.4.zip" -OutFile .\vendor\ffx-1.1.4.zip
cd .\vendor\
Expand-Archive ffx-1.1.4.zip .
Remove-Item ffx-1.1.4.zip

cd .\FidelityFX-SDK-1.1.4\sdk\

.\BuildFidelityFXSDK.bat -DFFX_BLUR=ON -DFFX_PARALLEL_SORT=ON -DFFX_API_BACKEND=DX12_X64 -DFFX_AUTO_COMPILE_SHADERS=1

cd ..\..\..

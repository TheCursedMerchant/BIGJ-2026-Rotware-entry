@echo off
echo Building BIGJ Entry

cd ./resources/textures
IF EXIST atlas.png DEL /F atlas.png
cd ../

odin run .. -out:../atlas-builder.exe
  
echo Build Finished.

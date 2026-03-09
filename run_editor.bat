@echo off
echo Building Kickboxing Editor

odin run editor/ -debug -out:./editor/main.exe
  
echo Editor Build Finished.

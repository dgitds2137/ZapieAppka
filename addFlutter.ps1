$flutterBin = "C:\Users\User\flutter\bin"
$machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")

if (($machinePath -split ";") -notcontains $flutterBin) {
    [Environment]::SetEnvironmentVariable(
        "Path",
        ($machinePath.TrimEnd(";") + ";" + $flutterBin),
        "Machine"
    )
}

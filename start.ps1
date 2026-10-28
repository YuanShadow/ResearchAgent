param(
    [ValidateRange(1, 65535)]
    [int]$Port = 8000,
    [switch]$Install,
    [switch]$CheckOnly
)

$ErrorActionPreference = 'Stop'
$previousPythonPath = $env:PYTHONPATH
$originalLocation = Get-Location

function Write-Step {
    param([string]$Message)
    Write-Host "... $Message" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Error {
    param([string]$Message)
    Write-Host "[FAIL] $Message" -ForegroundColor Red
}

function Write-Warning {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

Set-Location $PSScriptRoot
try {
    # Set up Python path
    $env:PYTHONPATH = Join-Path $PSScriptRoot 'src'
    if ($previousPythonPath) {
        $env:PYTHONPATH += ";$previousPythonPath"
    }

    # Check and create virtual environment
    $python = Join-Path $PSScriptRoot '.venv\Scripts\python.exe'
    if (-not (Test-Path -LiteralPath $python)) {
        if ($CheckOnly) {
            throw 'Virtual environment not found. Run start.bat to create it.'
        }

        Write-Step "Creating Python virtual environment..."
        $launcher = Get-Command py -ErrorAction SilentlyContinue
        if ($launcher) {
            & $launcher.Source -3 -m venv .venv 2>&1 | Out-Null
        } else {
            $pythonCmd = Get-Command python -ErrorAction SilentlyContinue
            if (-not $pythonCmd) {
                throw 'Python not found. Install Python 3.11 or newer and add it to PATH.'
            }
            & python -m venv .venv 2>&1 | Out-Null
        }

        if ($LASTEXITCODE -ne 0) {
            throw 'Failed to create virtual environment. Ensure Python 3.11+ is installed.'
        }
        Write-Success "Virtual environment created"
    }

    # Verify Python version
    Write-Step "Verifying Python version..."
    $versionCheck = & $python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}.{sys.version_info.micro}'); sys.exit(0 if sys.version_info >= (3, 11) else 1)" 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Python 3.11+ required. Current version in .venv: $versionCheck"
    }
    Write-Success "Python $versionCheck"

    # Check and install dependencies
    $probe = @"
import sys
try:
    import research_agent.cli, fastapi, uvicorn
    sys.exit(0)
except ImportError:
    sys.exit(1)
"@

    & $python -c $probe 2>&1 | Out-Null
    $needsInstall = $LASTEXITCODE -ne 0

    if ($CheckOnly -and $needsInstall) {
        throw 'Dependencies missing. Run start.bat to install them.'
    }

    if ($Install -or $needsInstall) {
        Write-Step "Installing dependencies from requirements.txt..."
        & $python -m pip install --quiet --upgrade pip 2>&1 | Out-Null
        & $python -m pip install --quiet -r requirements.txt

        if ($LASTEXITCODE -ne 0) {
            throw 'Dependency installation failed. Check network connection and requirements.txt.'
        }

        & $python -c $probe 2>&1 | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw 'Dependency verification failed after installation.'
        }
        Write-Success "Dependencies installed"
    } else {
        Write-Success "Dependencies verified"
    }

    # Check and create .env file
    if (-not (Test-Path -LiteralPath '.env')) {
        if ($CheckOnly) {
            throw 'Configuration file .env not found. Run start.bat to create it.'
        }

        if (Test-Path -LiteralPath '.env.example') {
            Copy-Item -LiteralPath '.env.example' -Destination '.env'
            Write-Warning "Created .env from template. Configure API keys before starting research."
        } else {
            Write-Warning ".env file missing and no .env.example template found."
        }
    }

    # Check port availability
    Write-Step "Checking port $Port availability..."
    $listener = [System.Net.Sockets.TcpListener]::new([System.Net.IPAddress]::Loopback, $Port)
    try {
        $listener.Start()
        $listener.Stop()
        Write-Success "Port $Port available"
    }
    catch {
        throw "Port $Port already in use. Stop existing service or use: start.bat -Port <other_port>"
    }

    # Start server or report check results
    if ($CheckOnly) {
        Write-Host ""
        Write-Success "All startup checks passed"
    } else {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "  ResearchAgent Server Starting" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  URL: http://127.0.0.1:$Port/" -ForegroundColor White
        Write-Host "  Stop: Press Ctrl+C" -ForegroundColor Gray
        Write-Host ""

        & $python -m research_agent.cli serve --host 127.0.0.1 --port $Port

        if ($LASTEXITCODE -ne 0) {
            throw "Server terminated with exit code $LASTEXITCODE"
        }
    }

} catch {
    Write-Host ""
    Write-Error "Startup failed: $($_.Exception.Message)"
    Write-Host ""
    exit 1

} finally {
    $env:PYTHONPATH = $previousPythonPath
    Set-Location $originalLocation
}

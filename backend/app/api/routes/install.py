"""
PolyTrader Installation Status Routes
Mirrors the PowerShell status dashboard.
"""

import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Dict, Any, List, Optional

import structlog
from fastapi import APIRouter, Query, HTTPException

logger = structlog.get_logger(__name__)
router = APIRouter()

# Get PolyTrader root from environment or default
POLYTRADER_ROOT = Path(os.environ.get("POLYTRADER_ROOT", "C:/Users/Default/Desktop/PolyTrader"))


# Installation steps configuration
INSTALL_STEPS = [
    {"step": "00", "name": "preflight_check", "marker": "preflight_ok.txt", "description": "System preflight check"},
    {"step": "01", "name": "install_dependencies", "marker": "deps_ok.txt", "description": "Install dependencies"},
    {"step": "02", "name": "setup_repo", "marker": "repo_ok.txt", "description": "Setup repository"},
    {"step": "03", "name": "setup_database", "marker": "db_ok.txt", "description": "Setup database"},
    {"step": "04", "name": "setup_api", "marker": "api_ok.txt", "description": "Setup API"},
    {"step": "05", "name": "setup_worker", "marker": "worker_dry_ok.txt", "description": "Setup worker"},
    {"step": "06", "name": "setup_dashboard", "marker": "ui_ok.txt", "description": "Setup dashboard"},
    {"step": "07", "name": "register_services", "marker": "services_ok.txt", "description": "Register services"},
    {"step": "08", "name": "final_verification", "marker": "final_ok.txt", "description": "Final verification"},
]


def get_marker_path(marker: str) -> Path:
    """Get full path to marker file."""
    return POLYTRADER_ROOT / "data" / marker


def get_log_dir() -> Path:
    """Get install logs directory."""
    return POLYTRADER_ROOT / "install-logs"


def check_marker(marker: str) -> Dict[str, Any]:
    """Check if a marker file exists and get its timestamp."""
    path = get_marker_path(marker)
    
    if path.exists():
        stat = path.stat()
        return {
            "exists": True,
            "timestamp": datetime.fromtimestamp(stat.st_mtime, tz=timezone.utc).isoformat(),
        }
    
    return {"exists": False, "timestamp": None}


def find_latest_log(step: str) -> Optional[Path]:
    """Find the most recent log file for a step."""
    log_dir = get_log_dir()
    
    if not log_dir.exists():
        return None
    
    pattern = f"STEP{step}*.log"
    logs = sorted(log_dir.glob(pattern), key=lambda p: p.stat().st_mtime, reverse=True)
    
    return logs[0] if logs else None


def determine_step_status(step_config: Dict, marker_status: Dict) -> str:
    """Determine step status based on marker and context."""
    if marker_status["exists"]:
        return "DONE"
    
    # Check if there's a log file (suggests it was attempted)
    log_file = find_latest_log(step_config["step"])
    if log_file:
        # Check if log indicates failure
        try:
            content = log_file.read_text(encoding="utf-8", errors="ignore")
            if "FAIL" in content or "ERROR" in content[-1000:]:
                return "LIKELY_FAILED"
        except:
            pass
        return "ATTEMPTED"
    
    return "NOT_DONE"


@router.get("/status")
async def get_install_status() -> Dict[str, Any]:
    """Get installation status for all steps."""
    steps_status = []
    
    for step_config in INSTALL_STEPS:
        marker_status = check_marker(step_config["marker"])
        status = determine_step_status(step_config, marker_status)
        
        log_file = find_latest_log(step_config["step"])
        log_hint = str(log_file.name) if log_file else None
        
        steps_status.append({
            "step": step_config["step"],
            "name": step_config["name"],
            "description": step_config["description"],
            "status": status,
            "marker": step_config["marker"],
            "marker_exists": marker_status["exists"],
            "marker_timestamp": marker_status["timestamp"],
            "log_file": log_hint,
        })
    
    # Determine next step
    next_step = None
    for step in steps_status:
        if step["status"] != "DONE":
            next_step = step["step"]
            break
    
    # Overall status
    done_count = sum(1 for s in steps_status if s["status"] == "DONE")
    total_count = len(steps_status)
    
    if done_count == total_count:
        overall_status = "COMPLETE"
    elif any(s["status"] == "LIKELY_FAILED" for s in steps_status):
        overall_status = "FAILED"
    elif done_count > 0:
        overall_status = "IN_PROGRESS"
    else:
        overall_status = "NOT_STARTED"
    
    return {
        "overall_status": overall_status,
        "progress": f"{done_count}/{total_count}",
        "steps": steps_status,
        "next_step": next_step,
        "next_script": f"{next_step}_{steps_status[int(next_step)]['name']}.ps1" if next_step else None,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }


@router.get("/logs/latest")
async def get_latest_log(
    step: str = Query(..., description="Step number (e.g., '00', '01')"),
) -> Dict[str, Any]:
    """Get the latest log file content for a step."""
    log_file = find_latest_log(step)
    
    if not log_file:
        raise HTTPException(
            status_code=404,
            detail=f"No log file found for step {step}",
        )
    
    try:
        content = log_file.read_text(encoding="utf-8", errors="ignore")
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to read log file: {str(e)}",
        )
    
    return {
        "step": step,
        "file": log_file.name,
        "content": content,
        "size_bytes": log_file.stat().st_size,
        "modified": datetime.fromtimestamp(
            log_file.stat().st_mtime, tz=timezone.utc
        ).isoformat(),
    }


@router.get("/logs/tail")
async def tail_log(
    step: str = Query(..., description="Step number"),
    lines: int = Query(default=200, ge=1, le=1000),
) -> Dict[str, Any]:
    """Get the last N lines of a log file."""
    log_file = find_latest_log(step)
    
    if not log_file:
        raise HTTPException(
            status_code=404,
            detail=f"No log file found for step {step}",
        )
    
    try:
        all_lines = log_file.read_text(encoding="utf-8", errors="ignore").splitlines()
        tail_lines = all_lines[-lines:]
    except Exception as e:
        raise HTTPException(
            status_code=500,
            detail=f"Failed to read log file: {str(e)}",
        )
    
    return {
        "step": step,
        "file": log_file.name,
        "lines": tail_lines,
        "line_count": len(tail_lines),
        "total_lines": len(all_lines),
    }


@router.get("/logs")
async def list_logs() -> Dict[str, Any]:
    """List all installation log files."""
    log_dir = get_log_dir()
    
    if not log_dir.exists():
        return {"logs": [], "count": 0}
    
    logs = []
    for log_file in sorted(log_dir.glob("*.log"), key=lambda p: p.stat().st_mtime, reverse=True):
        logs.append({
            "name": log_file.name,
            "size_bytes": log_file.stat().st_size,
            "modified": datetime.fromtimestamp(
                log_file.stat().st_mtime, tz=timezone.utc
            ).isoformat(),
        })
    
    return {
        "logs": logs,
        "count": len(logs),
        "directory": str(log_dir),
    }


@router.get("/recommendation")
async def get_recommendation() -> Dict[str, Any]:
    """Get recommendation for what to run next."""
    status = await get_install_status()
    
    recommendations = []
    
    # Check each step
    for step in status["steps"]:
        if step["status"] == "LIKELY_FAILED":
            recommendations.append({
                "action": "investigate",
                "step": step["step"],
                "message": f"Step {step['step']} ({step['name']}) appears to have failed. Check the log file.",
                "script": f"{step['step']}_{step['name']}.ps1",
            })
            break
        elif step["status"] == "NOT_DONE":
            recommendations.append({
                "action": "run",
                "step": step["step"],
                "message": f"Run step {step['step']}: {step['description']}",
                "script": f"{step['step']}_{step['name']}.ps1",
            })
            break
    
    if not recommendations:
        recommendations.append({
            "action": "complete",
            "message": "Installation is complete! All steps have succeeded.",
            "script": None,
        })
    
    return {
        "recommendations": recommendations,
        "overall_status": status["overall_status"],
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }

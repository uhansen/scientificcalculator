#!/usr/bin/env bash
# run-with-k8s-monitor.sh
#
# Runs the calculator stress test while simultaneously polling the Kubernetes
# cluster for pod counts and SpinApp / KEDA scaler status.
#
# Usage:
#   ./run-with-k8s-monitor.sh [options]
#
# Environment overrides (all optional):
#   URL            Target URL           (default: http://localhost:3000)
#   CONCURRENCY    Parallel workers     (default: 10)
#   DURATION       Test duration in s   (default: 30)
#   RAMP           Ramp-up time in s    (default: 5)
#   NAMESPACE      Kubernetes namespace (default: default)
#   SPINAPP_NAME   SpinApp resource name(default: thecalculatorspin)
#   POLL_INTERVAL  Seconds between k8s polls (default: 3)
#   DOTNET         Path to dotnet binary
#
# Example (longer run, higher concurrency):
#   DURATION=120 CONCURRENCY=50 ./run-with-k8s-monitor.sh

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

URL="${URL:-http://localhost:3000}"
CONCURRENCY="${CONCURRENCY:-10}"
DURATION="${DURATION:-30}"
RAMP="${RAMP:-5}"
NAMESPACE="${NAMESPACE:-default}"
SPINAPP_NAME="${SPINAPP_NAME:-thecalculatorspin}"
POLL_INTERVAL="${POLL_INTERVAL:-3}"

# ---------------------------------------------------------------------------
# Locate dotnet — prefer user-installed .NET 10 over system dotnet
# ---------------------------------------------------------------------------
if [ -n "${DOTNET:-}" ]; then
    : # use caller-supplied value
elif [ -x "${HOME}/.dotnet/dotnet" ] && "${HOME}/.dotnet/dotnet" --version 2>/dev/null | grep -q "^10\."; then
    DOTNET="${HOME}/.dotnet/dotnet"
elif command -v dotnet &>/dev/null && dotnet --version 2>/dev/null | grep -q "^10\."; then
    DOTNET="dotnet"
else
    echo "ERROR: .NET 10 SDK not found. Set DOTNET=/path/to/dotnet or install .NET 10." >&2
    exit 1
fi

# ---------------------------------------------------------------------------
# Colours
# ---------------------------------------------------------------------------
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

# ---------------------------------------------------------------------------
# Print header
# ---------------------------------------------------------------------------
echo ""
echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║     Calculator stress test  +  Kubernetes monitor        ║${NC}"
echo -e "${CYAN}╠══════════════════════════════════════════════════════════╣${NC}"
printf "${CYAN}║${NC}  SpinApp    : %-43s${CYAN}║${NC}\n" "${SPINAPP_NAME} (ns: ${NAMESPACE})"
printf "${CYAN}║${NC}  URL        : %-43s${CYAN}║${NC}\n" "${URL}"
printf "${CYAN}║${NC}  Duration   : %-43s${CYAN}║${NC}\n" "${DURATION}s  concurrency=${CONCURRENCY}  ramp=${RAMP}s"
printf "${CYAN}║${NC}  k8s poll   : every %-38s${CYAN}║${NC}\n" "${POLL_INTERVAL}s"
echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""

# ---------------------------------------------------------------------------
# kubectl commands used (printed for reference)
# ---------------------------------------------------------------------------
echo -e "${CYAN}kubectl commands used during monitoring:${NC}"
echo "  # Show SpinApp desired replicas"
echo "  kubectl get spinapp ${SPINAPP_NAME} -n ${NAMESPACE}"
echo ""
echo "  # Show running pods for the SpinApp"
echo "  kubectl get pods -n ${NAMESPACE} -l core.spinkube.dev/app=${SPINAPP_NAME}"
echo ""
echo "  # Show KEDA HTTPScaledObject (scale-to-zero configuration)"
echo "  kubectl get httpscaledobject ${SPINAPP_NAME} -n ${NAMESPACE}"
echo ""
echo "  # Watch pods live (run separately in another terminal):"
echo "  kubectl get pods -n ${NAMESPACE} -l core.spinkube.dev/app=${SPINAPP_NAME} -w"
echo ""
echo "  # Watch SpinApp live:"
echo "  kubectl get spinapp ${SPINAPP_NAME} -n ${NAMESPACE} -w"
echo ""
echo "──────────────────────────────────────────────────────────"
echo ""

# ---------------------------------------------------------------------------
# Background k8s monitor — polls every POLL_INTERVAL seconds
# ---------------------------------------------------------------------------
k8s_monitor() {
    local iteration=0
    while true; do
        sleep "${POLL_INTERVAL}"
        iteration=$((iteration + 1))

        echo ""
        echo -e "${YELLOW}┌── k8s status @ $(date '+%H:%M:%S') (poll #${iteration}) ──────────────────────┐${NC}"

        # SpinApp: desired and ready replicas
        SPINAPP_INFO=$(kubectl get spinapp "${SPINAPP_NAME}" -n "${NAMESPACE}" \
            -o jsonpath='desired={.spec.replicas} ready={.status.readyReplicas}' 2>/dev/null \
            || echo "not found")
        printf "${YELLOW}│${NC}  SpinApp replicas  : %-37s${YELLOW}│${NC}\n" "${SPINAPP_INFO}"

        # Pods matching the SpinApp label — use standard columns, simpler and more reliable
        POD_LINES=$(kubectl get pods -n "${NAMESPACE}" \
            -l "core.spinkube.dev/app=${SPINAPP_NAME}" \
            --no-headers 2>/dev/null || echo "")

        if [ -z "${POD_LINES}" ]; then
            # Try broad pod list if label yields nothing (label may differ per SpinKube version)
            POD_LINES=$(kubectl get pods -n "${NAMESPACE}" \
                --no-headers 2>/dev/null \
                | grep "^${SPINAPP_NAME}" || echo "  (none)")
        fi

        POD_COUNT=$(echo "${POD_LINES}" | grep -v '^\s*$' | grep -vc "(none)" 2>/dev/null || echo 0)

        printf "${YELLOW}│${NC}  Running pods      : %-37s${YELLOW}│${NC}\n" "${POD_COUNT}"
        while IFS= read -r line; do
            [ -n "${line}" ] && printf "${YELLOW}│${NC}    %-55s${YELLOW}│${NC}\n" "${line}"
        done <<< "${POD_LINES}"

        # KEDA HTTPScaledObject (if present)
        HSO_STATUS=$(kubectl get httpscaledobject "${SPINAPP_NAME}" -n "${NAMESPACE}" \
            -o jsonpath='ready={.status.conditions[?(@.type=="Ready")].status} scaleTarget={.spec.scaleTargetRef.name}' \
            2>/dev/null || echo "")
        if [ -n "${HSO_STATUS}" ]; then
            printf "${YELLOW}│${NC}  KEDA HTTPScaled   : %-37s${YELLOW}│${NC}\n" "${HSO_STATUS}"
        fi

        echo -e "${YELLOW}└──────────────────────────────────────────────────────────┘${NC}"
    done
}

# Start monitor in background, capture its PID
k8s_monitor &
MONITOR_PID=$!

# Kill monitor when this script exits for any reason
trap 'kill "${MONITOR_PID}" 2>/dev/null; echo ""' EXIT INT TERM

# ---------------------------------------------------------------------------
# Run the stress test (foreground — output goes directly to terminal)
# ---------------------------------------------------------------------------
echo -e "${GREEN}▶  Building stress test (silent)...${NC}"

cd "${SCRIPT_DIR}"

# Pre-build silently so MSBuild output doesn't mix with stress test output.
# Only rebuilds if source has changed (incremental).
"${DOTNET}" build calculatorstresstest.csproj -c Release --nologo -v quiet 2>&1 \
    | grep -E "error|Error|FAILED" || true

echo -e "${GREEN}▶  Starting stress test...${NC}"
echo ""

# Run the pre-built binary directly (no MSBuild output at runtime)
BINARY="${SCRIPT_DIR}/bin/Release/net10.0/calculaterstresstest"
if [ -x "${BINARY}" ]; then
    "${BINARY}" \
        --url          "${URL}" \
        --concurrency  "${CONCURRENCY}" \
        --duration     "${DURATION}" \
        --ramp         "${RAMP}"
else
    # Fallback: dotnet run with --no-build (binary was just built above)
    "${DOTNET}" run \
        --project calculatorstresstest.csproj \
        -c Release \
        --no-build \
        -- \
        --url          "${URL}" \
        --concurrency  "${CONCURRENCY}" \
        --duration     "${DURATION}" \
        --ramp         "${RAMP}"
fi

echo ""
echo -e "${GREEN}✔  Stress test complete.${NC}"
echo ""
echo -e "${CYAN}Note: pods will scale back to 0 after ~60 s of inactivity (KEDA scale-to-zero).${NC}"
echo -e "${CYAN}Run the following to watch scale-down:${NC}"
echo "  kubectl get pods -n ${NAMESPACE} -l core.spinkube.dev/app=${SPINAPP_NAME} -w"
echo ""

# trap fires here → monitor killed, newline printed

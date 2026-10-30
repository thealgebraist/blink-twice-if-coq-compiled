import time
import json
from pathlib import Path
import openai
from google import genai
from google.genai import types

# Define a non-trivial systems debugging & reasoning problem
TEST_PROBLEM = """You are diagnosing an intermittent production incident in a Kubernetes cluster running an NGINX ingress controller and a Go-based gRPC microservice.

--- PROBLEM REPORT ---
Clients occasionally receive HTTP 502 Bad Gateway or `rpc error: code = Unavailable desc = transport is closing` during rolling deployments or traffic spikes.
Analysis of tcpdump packet captures reveals the following sequence:
1. Client sends HTTP/2 request to NGINX ingress.
2. NGINX multiplexes the request to backend pod 10.244.3.42:50051 via an existing keepalive HTTP/2 connection.
3. Ingress sends DATA frame.
4. Backend pod immediately responds with a TCP RST or HTTP/2 GOAWAY frame with ErrCode NO_ERROR (0x0) or INTERNAL_ERROR (0x2), followed by FIN/RST.
5. Ingress logs:
   [error] 142#142: *892011 upstream prematurely closed connection while reading response header from upstream, client: 10.0.1.20, server: api.internal, request: "POST /order.OrderService/CreateOrder HTTP/2.0", upstream: "grpc://10.244.3.42:50051"

--- CONFIGURATIONS ---
1. NGINX upstream block:
   upstream grpc_backend {
       zone grpc_backend 64k;
       server 10.244.3.42:50051 max_fails=0;
       keepalive 100;
       keepalive_timeout 60s;
       keepalive_requests 10000;
   }
2. Go gRPC Server keepalive enforcement policy:
   keepalive.EnforcementPolicy{
       MinTime: 5 * time.Second,
       PermitWithoutStream: false,
   }
   ServerParameters:
   keepalive.ServerParameters{
       MaxConnectionAge: 30 * time.Second,
       MaxConnectionAgeGrace: 5 * time.Second,
   }
3. Kubernetes Service: ClusterIP, with Readiness Probe checking /healthz every 5s.

--- TASK ---
Provide a concise, precise technical diagnosis:
1. What is the race condition occurring between NGINX's HTTP/2 keepalive pooling and gRPC's MaxConnectionAge?
2. Why does NGINX return 502 rather than retrying on another upstream connection by default?
3. What is the specific fix needed on the NGINX ingress side and the Go gRPC server side to make connection draining 100% graceful without dropped in-flight RPCs?
"""

def test_luna_6_low():
    key = Path("openai.key.txt").read_text().strip()
    client = openai.OpenAI(api_key=key)

    start_time = time.perf_counter()
    response = client.responses.create(
        model="gpt-6-luna",
        input=TEST_PROBLEM,
        reasoning={"effort": "low"}
    )
    latency = time.perf_counter() - start_time

    output_text = response.output_text
    usage = response.usage
    in_tokens = usage.input_tokens
    out_tokens = usage.output_tokens
    reasoning_tokens = getattr(usage.output_tokens_details, "reasoning_tokens", 0) or 0
    total_tokens = usage.total_tokens

    # GPT-6 Luna pricing: $0.10 / 1M in, $0.50 / 1M out
    cost = (in_tokens / 1_000_000 * 0.10) + (out_tokens / 1_000_000 * 0.50)

    return {
        "model": "gpt-6-luna (OpenAI Responses API, effort=low)",
        "latency_sec": round(latency, 3),
        "input_tokens": in_tokens,
        "output_tokens": out_tokens,
        "reasoning_tokens": reasoning_tokens,
        "total_tokens": total_tokens,
        "est_price_usd": cost,
        "response_text": output_text
    }

def test_argon_low():
    key = Path("key.txt").read_text().strip()
    client = genai.Client(api_key=key)

    start_time = time.perf_counter()
    response = client.models.generate_content(
        model="gemini-4-argon",
        contents=TEST_PROBLEM,
        config=types.GenerateContentConfig(
            thinking_config=types.ThinkingConfig(thinking_budget=1024),
            temperature=0.2
        )
    )
    latency = time.perf_counter() - start_time

    output_text = response.text
    # Get token usage from response or count
    in_tokens = client.models.count_tokens(model="gemini-4-argon", contents=TEST_PROBLEM).total_tokens
    out_tokens = client.models.count_tokens(model="gemini-4-argon", contents=output_text).total_tokens
    # Add thinking tokens estimate or usage
    usage = getattr(response, "usage_metadata", None)
    if usage:
        in_tokens = getattr(usage, "prompt_token_count", in_tokens)
        out_tokens = getattr(usage, "candidates_token_count", out_tokens)
        total_tokens = getattr(usage, "total_token_count", in_tokens + out_tokens)
    else:
        total_tokens = in_tokens + out_tokens

    # Gemini 4 Argon pricing: $2.00 / 1M in, $10.00 / 1M out
    cost = (in_tokens / 1_000_000 * 2.00) + (out_tokens / 1_000_000 * 10.00)

    return {
        "model": "gemini-4-argon (Google GenAI API, budget=1024)",
        "latency_sec": round(latency, 3),
        "input_tokens": in_tokens,
        "output_tokens": out_tokens,
        "total_tokens": total_tokens,
        "est_price_usd": cost,
        "response_text": output_text
    }

def run_comparison():
    print("Testing OpenAI gpt-6-luna (effort=low)...")
    luna_result = test_luna_6_low()
    print(f"Luna done in {luna_result['latency_sec']}s")

    print("\nTesting Google gemini-4-argon (budget=1024)...")
    argon_result = test_argon_low()
    print(f"Argon done in {argon_result['latency_sec']}s")

    comparison = {
        "luna": luna_result,
        "argon": argon_result
    }

    with open("benchmark_results.json", "w") as f:
        json.dump(comparison, f, indent=2)

    print("\nBenchmark saved to benchmark_results.json")

if __name__ == "__main__":
    run_comparison()


import os
import time
import json
import subprocess
import concurrent.futures
from google import genai
from google.genai import types

api_key = open('key.txt').read().strip()
client = genai.Client(api_key=api_key)

# Representative Blink formalization benchmark task
benchmark_prompt = """You are an expert formalization agent auditing Chromium Blink CSS Layout.
Formalize the CSS Table percentage column width resolution rule:
For an available table width W_avail and percentage P (0 <= P <= 100),
the used column width is W_col = (W_avail * P) / 100.
Provide:
1. Pure Gallina constructive definition resolve_pct_col (w p : Z) : Z.
2. Theorem resolve_pct_col_nonneg: w >= 0 -> p >= 0 -> resolve_pct_col w p >= 0.
3. Theorem resolve_pct_col_monotonic: w1 <= w2 -> p >= 0 -> resolve_pct_col w1 p <= resolve_pct_col w2 p.
4. Theorem two_cols_pct_bounded: w >= 0 -> p1 >= 0 -> p2 >= 0 -> p1 + p2 <= 100 -> resolve_pct_col w p1 + resolve_pct_col w p2 <= w.
Enclose only clean Rocq/Coq code in a ```coq code block with 0 admits (closed by Qed)."""

def test_query(thinking_budget, max_output_tokens):
    t0 = time.time()
    try:
        response = client.models.generate_content(
            model="gemini-4-argon",
            contents=benchmark_prompt,
            config=types.GenerateContentConfig(
                max_output_tokens=max_output_tokens,
                thinking_config=types.ThinkingConfig(thinking_budget=thinking_budget)
            )
        )
        t1 = time.time()
        
        prompt_tokens = 0
        candidates_tokens = 0
        total_tokens = 0
        if hasattr(response, 'usage_metadata') and response.usage_metadata:
            prompt_tokens = getattr(response.usage_metadata, 'prompt_token_count', 0) or 0
            candidates_tokens = getattr(response.usage_metadata, 'candidates_token_count', 0) or 0
            total_tokens = getattr(response.usage_metadata, 'total_token_count', 0) or (prompt_tokens + candidates_tokens)

        # Check if Coq code block is present and compiles
        text = response.text
        has_coq = "```coq" in text
        coq_compiles = False
        if has_coq:
            try:
                coq_code = text.split("```coq")[1].split("```")[0]
                with open("/tmp/bench_test.v", "w") as f:
                    f.write("From Stdlib Require Import ZArith Lia.\nOpen Scope Z_scope.\n" + coq_code)
                res = subprocess.run(["coqc", "/tmp/bench_test.v"], capture_output=True, text=True, timeout=10)
                coq_compiles = (res.returncode == 0)
            except Exception:
                coq_compiles = False

        return {
            "success": True,
            "elapsed_sec": round(t1 - t0, 2),
            "prompt_tokens": prompt_tokens,
            "candidate_tokens": candidates_tokens,
            "total_tokens": total_tokens,
            "has_coq": has_coq,
            "coq_compiles": coq_compiles
        }
    except Exception as e:
        return {"success": False, "error": str(e), "elapsed_sec": round(time.time() - t0, 2)}

# 1. Benchmark Thinking Budgets: Low (512) vs Med (2048) vs High (8192)
print("--- Benchmarking Argon Thinking Budgets ---")
budgets = [
    ("Low (512)", 512, 3500),
    ("Medium (2048)", 2048, 3500),
    ("High (8192)", 8192, 4500)
]
budget_results = {}
for name, tb, max_tok in budgets:
    print(f"Testing {name}...")
    res = test_query(tb, max_tok)
    budget_results[name] = res
    print(f"  {name}: {res.get('elapsed_sec')}s, {res.get('total_tokens')} tokens, Coq compiles: {res.get('coq_compiles')}")

# 2. Benchmark Concurrency: 4 vs 8 vs 16 vs 32 agents
print("\n--- Benchmarking Agent Concurrency Levels (with Argon Low 512) ---")
concurrency_levels = [4, 8, 16]
concurrency_results = {}
for num_agents in concurrency_levels:
    print(f"Testing Concurrency = {num_agents} parallel workers...")
    t_start = time.time()
    with concurrent.futures.ThreadPoolExecutor(max_workers=num_agents) as executor:
        futures = [executor.submit(test_query, 512, 3000) for _ in range(num_agents)]
        results = [f.result() for f in futures]
    t_end = time.time()
    
    wall_time = round(t_end - t_start, 2)
    successful = sum(1 for r in results if r.get("success"))
    total_tokens = sum(r.get("total_tokens", 0) for r in results)
    compiles = sum(1 for r in results if r.get("coq_compiles"))
    avg_latency = round(sum(r.get("elapsed_sec", 0) for r in results) / len(results), 2)
    tokens_per_sec = round(total_tokens / wall_time, 1) if wall_time > 0 else 0
    
    stats = {
        "num_agents": num_agents,
        "wall_clock_sec": wall_time,
        "avg_agent_sec": avg_latency,
        "successful_queries": successful,
        "theories_compiled": compiles,
        "total_tokens": total_tokens,
        "throughput_tokens_per_sec": tokens_per_sec
    }
    concurrency_results[f"{num_agents}_agents"] = stats
    print(f"  {num_agents} Agents: Wall-clock={wall_time}s, Throughput={tokens_per_sec} tok/s, Compiled={compiles}/{num_agents}")

benchmark_summary = {
    "thinking_budgets": budget_results,
    "concurrency_scaling": concurrency_results
}

with open("benchmark_argon_scaling_results.json", "w") as f:
    json.dump(benchmark_summary, f, indent=2)

print("\nBenchmark complete! Saved to benchmark_argon_scaling_results.json.")


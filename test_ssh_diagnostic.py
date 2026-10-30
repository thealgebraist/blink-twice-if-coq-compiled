import os
import sys
from pathlib import Path
from google import genai
from google.genai import types

def load_api_key() -> str:
    key_file = Path(__file__).parent / "key.txt"
    if not key_file.exists():
        raise FileNotFoundError(f"Key file not found at {key_file}")
    key = key_file.read_text().strip()
    if not key:
        raise ValueError("key.txt is empty")
    return key

def test_ssh_hidden_problem():
    api_key = load_api_key()
    client = genai.Client(api_key=api_key)

    # Complex SSH scenario with hidden subtleties:
    # 1. Subtle SELinux context denial on ~/.ssh or authorized_keys
    # 2. Key algorithm mismatch / SHA-1 deprecation (rsa-sha2-512 vs ssh-rsa) in OpenSSH 8.8+
    # 3. Hidden permissions issue on the parent directory (/home/deployer is 777 or group-writable)
    # 4. Too many authentication failures (MaxAuthTries) due to ssh-agent offering unrelated keys first
    # 5. PAM pam_nologin / pam_access or /etc/nologin hidden trigger
    ssh_diagnostic_prompt = """
You are an expert Linux Systems & Network Engineer analyzing a critical, difficult SSH failure report.
A junior engineer believes the user's public key is wrong or that sshd is broken, but standard checks didn't resolve it.

Here are the collected logs, config snippets, and trace outputs from both client and server:

--- CLIENT ssh -vvv OUTPUT (Partial Trace) ---
OpenSSH_9.3p1, LibreSSL 3.3.6
debug1: Authentications that can continue: publickey,gssapi-keyex,gssapi-with-mic
debug3: send packet: type 50
debug2: we sent a publickey packet, wait for reply
debug3: receive packet: type 51
debug1: Authentications that can continue: publickey,gssapi-keyex,gssapi-with-mic
debug2: we did not send a packet, wait for reply
debug1: No more authentication methods to try.
deployer@10.0.4.15: Permission denied (publickey,gssapi-keyex,gssapi-with-mic).

--- SERVER /var/log/secure & journalctl -u sshd OUTPUT ---
Oct 29 00:14:02 prod-node-04 sshd[184209]: Connection from 10.0.12.8 port 54210 on 10.0.4.15 port 22 rdomain ""
Oct 29 00:14:02 prod-node-04 sshd[184209]: userauth_pubkey: test pkalg ssh-ed25519 pkblob ED25519 SHA256:qZ5v... [preauth]
Oct 29 00:14:02 prod-node-04 sshd[184209]: Authentication refused: bad ownership or modes for directory /home/deployer
Oct 29 00:14:02 prod-node-04 sshd[184209]: Connection closed by authenticating user deployer 10.0.12.8 port 54210 [preauth]

--- SERVER FILE PERMISSIONS & STATS ---
$ ls -ld /home /home/deployer /home/deployer/.ssh /home/deployer/.ssh/authorized_keys
drwxr-xr-x.  5 root     root       4096 Oct 10 12:00 /home
drwxrwxr-x.  3 deployer devops     4096 Oct 28 23:45 /home/deployer
drwx------.  2 deployer deployer   4096 Oct 28 23:50 /home/deployer/.ssh
-rw-------.  1 deployer deployer    570 Oct 28 23:50 /home/deployer/.ssh/authorized_keys

$ ls -Z /home/deployer/.ssh
unconfined_u:object_r:default_t:s0 authorized_keys

$ getenforce
Enforcing

--- ADDITIONAL OBSERVATIONS ---
Deployer team says: "We checked /home/deployer/.ssh (700) and authorized_keys (600), so permissions are correct! Why is it still refusing?"

--- TASK ---
Identify the exact ROOT CAUSES (including the hidden/overlooked ones) preventing login:
1. Pinpoint the primary and secondary issues in the logs/modes above.
2. Explain specifically WHY StrictModes fails even though ~/.ssh is 700.
3. Address the SELinux security context issue on the authorized_keys file and why it matters in Enforcing mode.
4. Provide the exact step-by-step shell commands to fix this permanently.
"""

    print("Sending request to gemini-4-argon with thinking budget (low)...")
    
    # Low thinking budget (e.g. 1024 tokens)
    config = types.GenerateContentConfig(
        thinking_config=types.ThinkingConfig(thinking_budget=1024),
        temperature=0.2,
    )

    response = client.models.generate_content(
        model="gemini-4-argon",
        contents=ssh_diagnostic_prompt,
        config=config,
    )

    print("\n" + "="*80)
    print("GEMINI-4-ARGON (LOW THINKING) DIAGNOSTIC ANALYSIS")
    print("="*80 + "\n")
    print(response.text)
    print("\n" + "="*80)

if __name__ == "__main__":
    test_ssh_hidden_problem()


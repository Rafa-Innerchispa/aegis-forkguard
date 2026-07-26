import os
from dulwich import porcelain

repo_path = "/home/usuario/.gemini/antigravity/scratch/aegis-forkguard"

porcelain.add(repo_path)
commit_id = porcelain.commit(
    repo_path,
    message=b"feat: AEGIS ForkGuard counterfactual execution firewall complete implementation",
    author=b"JacHacks Hacker <hacker@jachacks.org>",
    committer=b"JacHacks Hacker <hacker@jachacks.org>"
)

print(f"Git commit created successfully! Hash: {commit_id.decode('utf-8')}")

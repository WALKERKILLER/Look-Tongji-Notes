"""Allow `python3 -m llmwiki` to invoke the CLI."""
from llmwiki.cli import main
import sys

if __name__ == "__main__":
    sys.exit(main())

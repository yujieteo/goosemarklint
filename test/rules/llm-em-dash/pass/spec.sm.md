# Machine

## Requirements

- R1: The tool reads each file once. — src/main.goose:10
- R2: The tool is fast. — src/main.goose:20

## Bugs

- B1: Cancel during retry leaves the spinner on. — tests/cancel_retry.rs fails on 1a2b3c

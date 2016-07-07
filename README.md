# Build Your Own System 

Build a custom system offline from scratch

## Getting Started

Configuring your own system requires knowing what you want.

## Usage

```
./byos.sh --file=config/debian.conf [DEVICE] config/config-4.3.5 4.3.5
./byos.sh --file=config/debian.conf --grsec=grsecurity/grsecurity-3.1-4.3.5-201602092235.patch [DEVICE] config/config-4.3.5-grsec 4.3.5
```

## Task lists

- [ ] Check if packages are available
- [ ] Redirect all messages (errors, outputs, etc.) into one or more files
- [ ] Check if gcc plugin is available (for GRSEC)

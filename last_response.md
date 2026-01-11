```bash
#!/bin/bash
echo "Refactoring hello.py..."
cat <<EOF > hello.py
def say_hello(name):
    print(f"Hello, {name}!")

if __name__ == "__main__":
    say_hello("World")
EOF
echo "Verifying the change..."
python3 hello.py
echo "Success: hello.py has been refactored."
```

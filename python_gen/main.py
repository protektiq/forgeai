"""
Minimal Flask "hello world" service.
Run: python main.py
Then open http://localhost:5000/ or curl http://localhost:5000/
"""

from flask import Flask

app = Flask(__name__)


@app.route("/")
def index():
    return "Hello, world"


if __name__ == "__main__":
    app.run(host="0.0.0.0", port=5000, debug=True)

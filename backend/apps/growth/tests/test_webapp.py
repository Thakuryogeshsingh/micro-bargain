def test_web_app_served_with_spa_fallback(client):
    home = client.get("/app/")
    assert home.status_code == 200 and b'<base href="/app/">' in b"".join(home.streaming_content)
    assert client.get("/app/main.dart.js").status_code == 200
    # Unknown paths fall back to the app shell (the app routes itself).
    assert client.get("/app/some/deep/link").status_code == 200

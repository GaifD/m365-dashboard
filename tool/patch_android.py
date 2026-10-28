"""Дописывает в сгенерированный Android-проект разрешения Bluetooth и название приложения."""
import pathlib
import re

manifest = pathlib.Path("android/app/src/main/AndroidManifest.xml")
text = manifest.read_text(encoding="utf-8")

perms = [
    '<uses-permission android:name="android.permission.BLUETOOTH" android:maxSdkVersion="30" />',
    '<uses-permission android:name="android.permission.BLUETOOTH_ADMIN" android:maxSdkVersion="30" />',
    '<uses-permission android:name="android.permission.BLUETOOTH_SCAN" android:usesPermissionFlags="neverForLocation" />',
    '<uses-permission android:name="android.permission.BLUETOOTH_CONNECT" />',
    '<uses-permission android:name="android.permission.ACCESS_FINE_LOCATION" android:maxSdkVersion="30" />',
    '<uses-permission android:name="android.permission.WAKE_LOCK" />',
    '<uses-permission android:name="android.permission.FOREGROUND_SERVICE" />',
    '<uses-permission android:name="android.permission.FOREGROUND_SERVICE_CONNECTED_DEVICE" />',
    '<uses-permission android:name="android.permission.POST_NOTIFICATIONS" />',
    '<uses-permission android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS" />',
    '<uses-feature android:name="android.hardware.bluetooth_le" android:required="true" />',
]

if "BLUETOOTH_SCAN" not in text:
    if 'xmlns:tools=' not in text:
        text = text.replace("<manifest ", '<manifest xmlns:tools="http://schemas.android.com/tools" ', 1)
    m = re.search(r"<manifest[^>]*>", text)
    insert = "\n    " + "\n    ".join(perms) + "\n"
    text = text[: m.end()] + insert + text[m.end():]

text = re.sub(r'android:label="[^"]*"', 'android:label="M365 Dashboard"', text, count=1)

service = ('<service android:name=".RideService" android:exported="false" '
           'android:foregroundServiceType="connectedDevice" />')
if "RideService" not in text:
    idx = text.rfind("</application>")
    text = text[:idx] + "    " + service + "\n    " + text[idx:]
manifest.write_text(text, encoding="utf-8")
print("AndroidManifest patched")

# Свои Kotlin-файлы: MainActivity (канал m365/system, экран блокировки) и фоновая служба.
import shutil
kt_dir = pathlib.Path("android/app/src/main/kotlin/com/gaifd/m365_dashboard")
kt_dir.mkdir(parents=True, exist_ok=True)
copied = []
for f in pathlib.Path("tool/android").glob("*.kt"):
    shutil.copy(f, kt_dir / f.name)
    copied.append(f.name)
    print("copied", f.name)
assert "MainActivity.kt" in copied and "RideService.kt" in copied, f"native files missing: {copied}"

# своя иконка
res_src = pathlib.Path("tool/android/res")
icons = 0
for f in res_src.glob("mipmap-*/ic_launcher.png"):
    dst = pathlib.Path("android/app/src/main/res") / f.parent.name / f.name
    dst.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy(f, dst)
    icons += 1
assert icons == 5, f"icons copied: {icons}"
print("icons copied:", icons)


# Старые плагины (flutter_blue_plus) компилируются под android-33, а свежие androidx
# требуют 34+. Поднимаем compileSdk у всех библиотек-плагинов.
root_gradle = pathlib.Path("android/build.gradle.kts")
g = root_gradle.read_text(encoding="utf-8")
marker = "// m365: force plugin compileSdk"
if marker not in g:
    snippet = f'''
{marker}
subprojects {{
    afterEvaluate {{
        if (plugins.hasPlugin("com.android.library")) {{
            extensions.findByName("android")?.withGroovyBuilder {{
                "compileSdkVersion"(36)
            }}
        }}
    }}
}}
'''
    idx = g.find("subprojects {\n    project.evaluationDependsOn")
    if idx < 0:
        idx = g.find("project.evaluationDependsOn")
        idx = g.rfind("subprojects", 0, idx) if idx >= 0 else -1
    g = (g[:idx] + snippet.lstrip("\n") + "\n" + g[idx:]) if idx >= 0 else (g + snippet)
    root_gradle.write_text(g, encoding="utf-8")
    print("build.gradle.kts patched")

# Постоянный ключ подписи: без него каждая сборка подписывается новым случайным
# ключом, и обновление не ставится поверх старой версии.
app_gradle = pathlib.Path("android/app/build.gradle.kts")
ag = app_gradle.read_text(encoding="utf-8")
if 'create("stable")' not in ag:
    signing = '''    signingConfigs {
        create("stable") {
            storeFile = file("../../tool/debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

'''
    idx = ag.find("    buildTypes {")
    assert idx >= 0, "buildTypes not found in app/build.gradle.kts"
    ag = ag[:idx] + signing + ag[idx:]
    assert 'signingConfig = signingConfigs.getByName("debug")' in ag, "release signingConfig line not found"
    ag = ag.replace('signingConfig = signingConfigs.getByName("debug")',
                    'signingConfig = signingConfigs.getByName("stable")')
    app_gradle.write_text(ag, encoding="utf-8")
    print("app/build.gradle.kts: stable signing")

# Без обфускации/вырезания кода R8: плагины (shared_preferences и др.) вызывают
# свои методы через рефлексию/корутины, и R8 их вырезает → NoSuchMethodError в release.
ag = app_gradle.read_text(encoding="utf-8")
if "isMinifyEnabled = false" not in ag:
    anchor = 'signingConfig = signingConfigs.getByName("stable")'
    assert anchor in ag, "stable signingConfig line not found"
    ag = ag.replace(anchor, anchor + "\n            isMinifyEnabled = false\n            isShrinkResources = false")
    app_gradle.write_text(ag, encoding="utf-8")
    print("app/build.gradle.kts: minify off")
print(app_gradle.read_text(encoding="utf-8"))

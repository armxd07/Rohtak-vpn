# Rohtak VPN — Android VPN App (Full Source Code)

**28.875089, 76.637220 — Rohtak, Haryana (India)** ke naam pe ek complete Android VPN app.

Ye app **WireGuard protocol** (official `com.wireguard.android:tunnel` library — Go backend) use karta hai. Ek private WireGuard server (VPS) se secure tunnel banata hai, aur aapka internet traffic server ke IP se bahar jata hai — matlab **aapka public IP = VPS ka IP** ban jata hai.

---

## 1. Ye Kaise Kaam Karta Hai

```
Phone (Rohtak VPN app)
      |  WireGuard encrypted tunnel (UDP 51820)
      v
VPS Server (India / Delhi NCR region)  ----->  Internet
      (aapka public IP yahan ka dikhega)
```

- App phone pe saara traffic ko encrypt karke VPS bhejta hai.
- VPS us traffic ko internet pe forward karta hai (NAT/MASQUERADE).
- Websites ko VPS ka IP dikhta hai — jo India region ka hoga.
- **Important:** Rohtak exact me koi datacenter nahi hota. VPS **Delhi NCR (Noida/Delhi/Gurgaon)** ya **Mumbai** region ka lena — wahi aapke location ke sabse paas hoga aur lowest ping dega.

---

## 2. Project Structure

```
RohtakVPN/
├── app/                          # Android app ka pura source code
│   └── src/main/
│       ├── java/com/rohtak/vpn/
│       │   ├── VpnApp.kt         # Application class (GoBackend init)
│       │   └── MainActivity.kt   # Connect button, QR import, stats — sab yahan
│       ├── res/                  # UI (dark theme, power button, icons)
│       └── AndroidManifest.xml   # Permissions + GoBackend VpnService
├── server/
│   ├── wireguard-server.sh       # VPS pe WireGuard 1-click setup
│   └── add-client.sh             # Naye devices add karne ke liye
├── build.gradle                  # AGP 8.5.2, Kotlin 1.9.24
├── settings.gradle
└── gradle/wrapper/               # Gradle 8.7 config
```

---

## 3. Zaroori Cheezein (Requirements)

| Cheez | Detail |
|---|---|
| VPS | Ubuntu 22.04, kam se kam 1 CPU / 512 MB RAM, India region |
| Android Studio | Latest stable (Ladybug ya newer) — JDK 17 bundled hota hai |
| Phone | Android 7.0 (API 24) ya newer |
| Internet | VPS pe UDP port 51820 khula hona chahiye |

**VPS providers (India region):** E2E Networks (Noida/Delhi NCR), AWS Lightsail (Mumbai), DigitalOcean (Bangalore), Hostinger (India), Contabo, etc. Sabse kam ping ke liye Delhi NCR wala chuno.

---

## 4. Step 1 — Server Setup (VPS pe)

VPS ban jane ke baad SSH se login karo:

```bash
ssh root@<VPS_KA_IP>
```

Script upload karo aur chala do:

```bash
# Apne PC se VPS pe script bhejo
scp server/wireguard-server.sh root@<VPS_KA_IP>:/root/

# VPS pe
cd /root
bash wireguard-server.sh <VPS_KA_IP>
```

Script apne aap sab kuch kar dega. Last me ek **QR code** terminal pe print hoga — wo phone me import karna hai (Step 3 me).

**Client config backup:** `/root/rohtak-vpn/rohtak-client1.conf` — is file ka khayal rakho.

**Naya device add karna ho to:**

```bash
scp server/add-client.sh root@<VPS_KA_IP>:/root/
ssh root@<VPS_KA_IP> "bash add-client.sh mera-dusra-phone"
```

---

## 5. Step 2 — APK Build Karna (Android Studio me)

1. **Android Studio** kholo (agar nahi hai to developer.android.com/studio se download karo).
2. `File > Open` → ye `RohtakVPN` folder select karo.
3. Gradle sync hone do (pehli baar internet pe dependencies download hongi — 5-10 min lag sakte hain).
4. Build karo:
   - **Direct APK:** Menu me `Build > Build App Bundle(s) / APK(s) > Build APK(s)`
   - APK yahan milega: `app/build/outputs/apk/debug/app-debug.apk`
5. Is APK ko phone me install karo (USB se copy karke ya `adb install app-debug.apk`).

**Command line se build karna ho to** (Studio ke bahar):

```bash
# JDK 17 + Gradle 8.7 chahiye
gradle assembleDebug
```

> Note: Wrapper scripts (gradlew) is zip me nahi hain — Android Studio khud Gradle 8.7 download kar lega `gradle/wrapper/gradle-wrapper.properties` se. Command line use karna ho to `gradle wrapper` chala ke gradlew generate kar lo.

### App me changes karna ho to:

- **App ka naam:** `app/src/main/res/values/strings.xml` → `app_name`
- **Colors/theme:** `res/values/colors.xml`, `res/values/themes.xml`
- **Logic:** `MainActivity.kt` (connect/disconnect, stats, import)

---

## 6. Step 3 — App Me Config Import + Connect

1. App kholo — pehli baar **DISCONNECTED** dikhega.
2. **"QR se Import"** dabao → VPS terminal pe jo QR print hua tha wo scan karo.
   - (Ya VPS se `rohtak-client1.conf` file phone me bhejo aur **".conf File"** se import karo.)
3. Bada **power button** dabao → Android ka VPN permission dialog aayega → **OK** karo.
4. Status **CONNECTED** (green) ho jayega. Ab `whatismyipaddress.com` kholo — VPS ka IP dikhna chahiye.

Stats section me live **RECEIVED / SENT / TIME** update hote rehte hain.

---

## 7. Troubleshooting (Common Problems)

| Problem | Solution |
|---|---|
| Gradle sync fail — "desugaring" error | `app/build.gradle` me `coreLibraryDesugaringEnabled true` hai? Ye line delete mat karna. |
| "Unsupported class major version" build error | JDK 17 use karo (Studio: `Settings > Build Tools > Gradle > Gradle JDK = 17`). |
| Connect dabane pe dialog hi nahi aaya | Doosri VPN app active hai? Pehle usko disconnect karo — Android ek time pe ek VPN chalata hai. |
| Connected but internet nahi chal raha | VPS pe check karo: `wg show` (handshake dikhe?), `sysctl net.ipv4.ip_forward` (=1?), firewall me UDP 51820 open hai? |
| Handshake nahi ho raha | VPS provider ke firewall/cloud console me UDP 51820 allow karo. Endpoint IP:port galat to nahi? |
| App ka IP foreign dikha | VPS India region ka nahi hai — Delhi NCR/Mumbai region ka VPS lo. |
| App crash ho jata hai | `adb logcat` me error dekho, ya Studio se "Run" karke debug karo. |

---

## 8. Security Notes

- Client private key (`rohtak-client1.key` / `.conf`) **kisi se share mat karo** — jiske paas config hai wahi aapke server se internet use kar sakta hai.
- `add-client.sh` se har device ka alag config banao — ek config do devices pe use karne se collision hota hai.
- Server keys `/etc/wireguard/` me `600` permission ke saath hain.
- App me `allowBackup=false` rakha hai taaki config system backup me leak na ho.
- Server pe sirf zaroori ports kholo (`ufw`), SSH ke liye key auth use karo.

## 9. Legal Note

Ye code apne **khud ke server** aur **legal purposes** ke liye use karo. VPN banana/use karna legal hai, lekin iske through illegal activities karna to nahi — server provider ke ToU aur local laws follow karo.

---

## Quick APK build (without Android Studio on your own computer)

This repository includes a GitHub Actions workflow at `.github/workflows/build-apk.yml`.

1. Create a new GitHub repository and upload the contents of this project (the files inside `RohtakVPN`, not the parent folder).
2. Open the repository's **Actions** tab and select **Build RohtakVPN APK**.
3. Press **Run workflow** (or push the code to the `main` branch).
4. When the run completes successfully, open that run and download the **RohtakVPN-debug-apk** artifact. Extract it to get `app-debug.apk`.
5. Transfer `app-debug.apk` to your Android phone and install it. Android may ask you to allow installs from that source.

The workflow builds a debug APK; it is not a signed Play Store release. VPN connection will only work after you configure and run a WireGuard server and import its client configuration into the app.

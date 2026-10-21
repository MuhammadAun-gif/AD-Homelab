# Active Directory Home Lab — Windows Server 2022 + Windows 11

**Author:** Muhammad Aun Hasan · **Built:** 12–17 October 2026 · **Platform:** VMware Workstation

**Disclaimer:** used AI fro report writing and Readme, conducted the project myself as well as the images and scripts were made by me

I built a small company network from scratch inside virtual machines: a Windows Server 2022 **Domain Controller** (the server that stores every user, computer and rule for the network) and a Windows 11 **workstation** joined to it. I then set it up the way a real IT team would — departments, user accounts, a security group, a protected file share, and **Group Policy** (rules the server pushes to every computer automatically) — and tested that each piece actually works. I also wrote a PowerShell script to create new users automatically.

> Built while following a guided Active Directory course; all configuration, testing and write-up are my own.

---

## Contents

1. [Lab at a glance](#1-lab-at-a-glance)
2. [Network diagram](#2-network-diagram)
3. [Skills shown](#3-skills-shown)
4. [Step-by-step build](#4-step-by-step-build)
5. [PowerShell automation](#5-powershell-automation)
6. [Test results](#6-test-results)
7. [Glossary of short forms](#7-glossary-of-short-forms)
8. [Disclaimer](#disclaimer)

---

## 1. Lab at a glance

| Item | Value |
|---|---|
| Domain name | `LAB.local` (short NetBIOS name: `LAB`) |
| Domain Controller | **DC01** — Windows Server 2022 Standard (evaluation), 8 GB RAM, 4 CPUs, 60 GB disk |
| Server roles | Active Directory Domain Services (AD DS), DNS Server, Active Directory Certificate Services (AD CS), File Server |
| Workstation | **WS01** — Windows 11, 8 GB RAM, 4 CPUs, 64 GB disk |
| Virtual network | VMware **VMnet8 (NAT)**, `10.0.2.0/24`, gateway `10.0.2.2` |
| IP addresses (fixed) | DC01 = `10.0.2.129` · WS01 = `10.0.2.128` |
| DNS | DC01 points to itself (`127.0.0.1`); WS01 points to DC01 (`10.0.2.129`) |
| Forest / domain level | Windows Server 2016 |
| Certificate Authority | Enterprise Root CA `LAB-DC01-CA`, RSA 2048-bit key, SHA-256, valid 5 years |

**Directory layout I created**

```
LAB.local
├── Engineering (OU)        ← Group Policy "SetEngineeringWallpaper" linked here
│   ├── john doe            (jdoe)
│   ├── lorem ispum         (lispum)
│   └── EngineeringShare    (security group)
├── Management (OU)
│   ├── Ahmed Rizwan        (ahrizwan)
│   └── hasan ali
├── IT (OU)
│   ├── Administrator
│   └── Admin (OU)
└── Computers
    └── WS01
```

**EngineeringShare group members:** john doe, lorem ispum, hasan ali
*(hasan ali sits in Management but was added on purpose — this proves that access comes from the group, not from the department folder he lives in.)*

---

## 2. Network diagram

```mermaid
flowchart LR
    subgraph HOST["My laptop - VMware Workstation"]
        subgraph NET["VMnet8 (NAT) 10.0.2.0/24 - gateway 10.0.2.2"]
            DC["DC01 - Windows Server 2022<br/>10.0.2.129<br/>AD DS + DNS + AD CS + File share"]
            WS["WS01 - Windows 11<br/>10.0.2.128<br/>DNS points to DC01"]
        end
    end
    WS -- "domain logon, Group Policy,<br/>EngineeringShare (SMB)" --> DC
    NET -- "internet via NAT" --> INET(("Internet"))
```

---

## 3. Skills shown

- Installing Windows Server 2022 in VMware and taking **snapshots** (restore points) before risky changes
- Promoting a server to a **Domain Controller** and creating a new forest (`LAB.local`)
- Setting up a **Certificate Authority** (AD CS) for the domain
- Planning a virtual network, fixed IP addresses and **DNS** so a client can find the domain
- Joining a Windows 11 computer to the domain and logging in with domain accounts
- Organising users into **Organisational Units (OUs)** by department
- Using **security groups** and **NTFS permissions** to control who can open a file share (least-access design)
- Creating and linking **Group Policy Objects (GPOs)** to a department
- Writing a **PowerShell** script to create users with random temporary passwords
- Testing every change with both an allowed user and a denied user

---

## 4. Step-by-step build

### Part A — Build the server (12 Oct)

**A1. Download Windows Server 2022** from the Microsoft Evaluation Center and create a new VMware virtual machine.

<p align="center"><img src="images/01-download-server-2022.png" width="720" alt="Microsoft Evaluation Center page for Windows Server 2022"><br><em>Figure 1 — Windows Server 2022 evaluation download</em></p>

<p align="center"><img src="images/02-vm-hardware.png" width="720" alt="VMware settings for the server VM"><br><em>Figure 2 — Server VM hardware: 8 GB RAM, 4 processors, 60 GB disk</em></p>

**A2. Take a snapshot** right after installing, so I can roll back if anything breaks later.

<p align="center"><img src="images/03-snapshot-manager.png" width="620" alt="VMware Snapshot Manager showing Snapshot 1"><br><em>Figure 3 — "Snapshot 1" saved as a clean restore point</em></p>

**A3. Rename the server to `DC01`** (a clear name before it becomes a domain controller, because renaming afterwards is harder).

<p align="center"><img src="images/04-rename-dc01.png" width="620" alt="Rename your PC dialog with DC01"><br><em>Figure 4 — Renaming the server to DC01</em></p>

**A4. Install Active Directory Domain Services** through *Server Manager → Manage → Add Roles and Features*.

<p align="center"><img src="images/05-add-adds-role.png" width="620" alt="Add Roles wizard with AD DS ticked"><br><em>Figure 5 — Selecting the Active Directory Domain Services role</em></p>

**A5. Promote the server to a Domain Controller** and create a new forest called `LAB.local`. I kept DNS Server and Global Catalog ticked and set a recovery (DSRM) password.

<p align="center"><img src="images/06-new-forest-lab-local.png" width="620" alt="Deployment configuration: add a new forest LAB.local"><br><em>Figure 6 — New forest, root domain LAB.local</em></p>

<p align="center"><img src="images/07-dc-options.png" width="620" alt="Domain controller options"><br><em>Figure 7 — Functional level Windows Server 2016, DNS and Global Catalog enabled</em></p>

<p align="center"><img src="images/08-prerequisites-check.png" width="620" alt="Prerequisites check passed with warnings"><br><em>Figure 8 — Prerequisite check passed. One warning says the server has no fixed IP address yet — I fix this in Part C.</em></p>

**A6. Install Active Directory Certificate Services** and configure an **Enterprise Root Certificate Authority**. This lets the domain issue its own certificates, which secure versions of protocols (for example LDAPS, encrypted directory lookups) need.

<p align="center"><img src="images/09-enterprise-root-ca.png" width="620" alt="AD CS confirmation page"><br><em>Figure 9 — CA type Enterprise Root, name LAB-DC01-CA, 2048-bit key, SHA-256</em></p>

### Part B — Create domain users (16 Oct)

Opened *Active Directory Users and Computers* and created four users: Ahmed Rizwan, hasan ali, john doe and lorem ispum.

<p align="center"><img src="images/10-new-user-ahmed-rizwan.png" width="520" alt="New user dialog for Ahmed Rizwan"><br><em>Figure 10 — Creating Ahmed Rizwan, logon name ahrizwan@LAB.local</em></p>

<p align="center"><img src="images/11-domain-users-created.png" width="620" alt="Users container with four new users"><br><em>Figure 11 — All four users created</em></p>

### Part C — Network and fixed IP addresses (16 Oct)

**C1.** The server was first on VMware's *host-only* network with an automatic address. I moved **both VMs to VMnet8 (NAT)** and set its subnet to `10.0.2.0/24`, so the server and the workstation share one network that can also reach the internet.

<p align="center"><img src="images/12-vmnet8-nat-10-0-2-0.png" width="620" alt="VMware Virtual Network Editor"><br><em>Figure 12 — VMnet8 set to NAT, subnet 10.0.2.0</em></p>

<p align="center"><img src="images/13-client-on-vmnet8.png" width="620" alt="Windows 11 VM network adapter set to VMnet8"><br><em>Figure 13 — Windows 11 VM network adapter set to VMnet8 (NAT)</em></p>

**C2. Give DC01 a fixed IP address.** A domain controller must never change address, because every computer finds the domain through it. DNS is set to `127.0.0.1` (itself), because DC01 is the domain's DNS server.

<p align="center"><img src="images/14-dc-static-ip.png" width="720" alt="DC01 IPv4 properties"><br><em>Figure 14 — DC01: IP 10.0.2.129, gateway 10.0.2.2, DNS 127.0.0.1</em></p>

### Part D — Join the Windows 11 workstation (16 Oct)

**D1. Rename the workstation to `WS01`.**

<p align="center"><img src="images/15-rename-client-ws01.png" width="560" alt="Rename PC to WS01"><br><em>Figure 15 — Renaming the client to WS01</em></p>

**D2. Fixed IP and DNS pointing to DC01.** This is the key step: a computer can only find the domain `LAB.local` if it asks the domain's own DNS server.

<p align="center"><img src="images/16-client-static-ip-dns.png" width="720" alt="WS01 IPv4 properties"><br><em>Figure 16 — WS01: IP 10.0.2.128, gateway 10.0.2.2, DNS 10.0.2.129 (DC01)</em></p>

**D3. Join the domain** from *Settings → Accounts → Access work or school → Join this device to a local Active Directory domain*.

<p align="center"><img src="images/17-join-domain.png" width="720" alt="Join a domain dialog"><br><em>Figure 17 — Joining WS01 to LAB.local</em></p>

**D4. Log in as a domain user** and confirm WS01 appears on the server.

<p align="center"><img src="images/18-domain-login-ahrizwan.png" width="460" alt="Windows 11 login as ahrizwan, sign in to LAB"><br><em>Figure 18 — Logging in to WS01 as ahrizwan ("Sign in to: LAB")</em></p>

<p align="center"><img src="images/19-ws01-in-computers.png" width="620" alt="WS01 listed in Computers"><br><em>Figure 19 — WS01 now listed under Computers on DC01</em></p>

### Part E — Organise users into departments (17 Oct)

Created **Organisational Units** — Engineering, Management and IT (with an Admin OU inside IT) — and moved each user into their department. This matters because Group Policy can be linked to an OU, but **not** to the built-in "Users" folder.

<p align="center"><img src="images/20-new-ou.png" width="460" alt="New Organizational Unit dialog"><br><em>Figure 20 — Creating an OU, with "Protect from accidental deletion" ticked</em></p>

<p align="center"><img src="images/22-engineering-ou-users.png" width="620" alt="Engineering OU with john doe and lorem ispum"><br><em>Figure 21 — Engineering: john doe, lorem ispum</em></p>

<p align="center"><img src="images/23-management-ou-users.png" width="620" alt="Management OU with Ahmed Rizwan and hasan ali"><br><em>Figure 22 — Management: Ahmed Rizwan, hasan ali</em></p>

<p align="center"><img src="images/24-it-admin-ou.png" width="620" alt="IT OU containing the Admin OU"><br><em>Figure 23 — IT, with a nested Admin OU</em></p>

### Part F — Security group (17 Oct)

Created a **Global Security group** called `EngineeringShare` and added john doe, lorem ispum and hasan ali.

<p align="center"><img src="images/25-engineeringshare-group.png" width="420" alt="EngineeringShare group properties"><br><em>Figure 24 — Group scope Global, group type Security</em></p>

<p align="center"><img src="images/26-group-members.png" width="420" alt="EngineeringShare members"><br><em>Figure 25 — Members: hasan ali (Management), john doe and lorem ispum (Engineering)</em></p>

### Part G — Protected file share (17 Oct)

**G1.** In *Server Manager → File and Storage Services → Shares → New Share*, created **SMB Share – Quick** at `C:\Shares\EngineeringShare` (network path `\\DC01\EngineeringShare`).

<p align="center"><img src="images/27-new-share-path.png" width="620" alt="New Share Wizard share name"><br><em>Figure 26 — Share name and paths</em></p>

**G2. Lock down the folder permissions (NTFS).** I turned off inheritance (so the folder stops copying permissions from `C:\`), **removed the general "Users" group** (which would let every domain user in), and then gave the `EngineeringShare` group access.

<p align="center"><img src="images/28-inheritance-disabled.png" width="620" alt="Advanced security with inheritance disabled"><br><em>Figure 27 — Inheritance disabled; the general Users entry is still there</em></p>

<p align="center"><img src="images/29-users-removed.png" width="620" alt="Users group removed"><br><em>Figure 28 — Users group removed: only SYSTEM, Administrators and CREATOR OWNER left</em></p>

<p align="center"><img src="images/30-group-permission-entry.png" width="720" alt="Permission entry for EngineeringShare"><br><em>Figure 29 — EngineeringShare group added</em></p>

<p align="center"><img src="images/31-final-permissions.png" width="620" alt="Final permissions summary"><br><em>Figure 30 — Final permissions. Share level: Everyone. Folder (NTFS) level: only EngineeringShare, Administrators and SYSTEM.</em></p>

<p align="center"><img src="images/32-share-created.png" width="620" alt="Share created successfully"><br><em>Figure 31 — Share created</em></p>

### Part H — Test who can open the share (17 Oct)

| User | Department (OU) | In EngineeringShare group? | Expected | Result |
|---|---|---|---|---|
| Ahmed Rizwan | Management | No | Blocked | ✅ Blocked |
| hasan ali | Management | **Yes** | Allowed | ✅ Allowed — created a folder and mapped drive Z: |

<p align="center"><img src="images/33-access-denied-ahmed.png" width="560" alt="Windows cannot access DC01 EngineeringShare"><br><em>Figure 32 — Ahmed Rizwan: "You do not have permission to access \\DC01\EngineeringShare"</em></p>

<p align="center"><img src="images/34-access-granted-hasan.png" width="720" alt="hasan ali inside EngineeringShare"><br><em>Figure 33 — hasan ali opens the share</em></p>

<p align="center"><img src="images/35-map-network-drive.png" width="520" alt="Map network drive Z"><br><em>Figure 34 — Mapping the share as drive Z:, reconnect at sign-in</em></p>

<p align="center"><img src="images/36-mapped-z-drive.png" width="720" alt="Z drive in This PC"><br><em>Figure 35 — EngineeringShare (\\DC01) (Z:) under Network locations</em></p>

### Part I — Group Policy: department wallpaper (17 Oct)

**I1.** Made an "Engineering Department" wallpaper and saved it in the server's **NETLOGON** share, a folder every domain computer can already read.

<p align="center"><img src="images/37-wallpaper-image.png" width="560" alt="Wallpaper made in Paint"><br><em>Figure 36 — Wallpaper image</em></p>

<p align="center"><img src="images/38-wallpaper-in-netlogon.png" width="620" alt="Wallpaper file in NETLOGON"><br><em>Figure 37 — Engineering_dept_wallpaper.png in \\DC01.LAB.local\NETLOGON</em></p>

**I2.** In *Group Policy Management*, created and linked a GPO called `SetEngineeringWallpaper` to the **Engineering** OU, then set *User Configuration → Administrative Templates → Desktop → Desktop → Desktop Wallpaper* to the network path of the image.

<p align="center"><img src="images/39-gpo-created-engineering.png" width="620" alt="New GPO dialog"><br><em>Figure 38 — Creating the GPO on the Engineering OU</em></p>

<p align="center"><img src="images/40-gpo-linked.png" width="620" alt="GPO linked and enabled"><br><em>Figure 39 — Linked and enabled</em></p>

<p align="center"><img src="images/41-desktop-wallpaper-setting.png" width="620" alt="Desktop Wallpaper policy enabled"><br><em>Figure 40 — Desktop Wallpaper enabled, pointing to \\DC01.LAB.local\NETLOGON\…</em></p>

**I3. Test:** logged in as Engineering user **jdoe** — the wallpaper was applied automatically.

<p align="center"><img src="images/42-login-jdoe.png" width="460" alt="Login as jdoe"><br><em>Figure 41 — Logging in as jdoe</em></p>

<p align="center"><img src="images/43-wallpaper-applied.png" width="720" alt="Engineering Department wallpaper on desktop"><br><em>Figure 42 — Group Policy applied: Engineering wallpaper on the desktop</em></p>

**I4.** Created a second GPO, `DisableChangingWallpaper`, and enabled *User Configuration → Administrative Templates → Control Panel → Personalization → Prevent changing desktop background*, so users cannot replace the company wallpaper.

<p align="center"><img src="images/44-prevent-changing-background.png" width="620" alt="Prevent changing desktop background enabled"><br><em>Figure 43 — "Prevent changing desktop background" enabled</em></p>

---

## 5. PowerShell automation

[`scripts/Create-ADUser.ps1`](scripts/Create-ADUser.ps1) creates a domain user in one command instead of clicking through the wizard. It worked in the lab.

```powershell
.\Create-ADUser.ps1 -FirstName John -Lastname Doe -Username jdoe -OU Engineering -Domain LAB.local
```

**What it does**

1. Takes first name, last name, username, OU and domain as required inputs
2. Generates a random 12-character temporary password and shows it once
3. Converts the password to a secure string so it is handed to Active Directory safely
4. Creates the account enabled, in the chosen OU, with **"must change password at next logon"** turned on and password expiry left on

---

## 6. Test results

| # | Test | Expected | Result |
|---|---|---|---|
| 1 | WS01 joins `LAB.local` | Join succeeds | ✅ Pass |
| 2 | Domain user logs in on WS01 | Login works | ✅ Pass |
| 3 | Ahmed Rizwan (not in group) opens the share | Blocked | ✅ Pass — blocked |
| 4 | hasan ali (in group) opens the share and creates a folder | Allowed | ✅ Pass |
| 5 | Map the share as drive Z: | Drive appears | ✅ Pass |
| 6 | Engineering user logs in | Engineering wallpaper applied | ✅ Pass |
| 7 | `Create-ADUser.ps1` creates a user | User created | ✅ Pass |

---

## 7. Glossary of short forms

| Short form | Meaning |
|---|---|
| AD | Active Directory — Microsoft's central list of users, computers and rules for a network |
| AD DS | Active Directory Domain Services — the server role that runs Active Directory |
| AD CS | Active Directory Certificate Services — the role that issues digital certificates |
| CA | Certificate Authority — the service that signs and issues certificates |
| DC | Domain Controller — the server that runs AD and checks every login |
| DNS | Domain Name System — turns names (like `DC01.LAB.local`) into IP addresses |
| DSRM | Directory Services Restore Mode — a recovery mode for a domain controller, with its own password |
| GPO | Group Policy Object — a set of rules pushed automatically to users or computers |
| IP | Internet Protocol address — a computer's number on the network |
| LDAPS | LDAP over SSL — encrypted directory lookups (LDAP = Lightweight Directory Access Protocol) |
| NAT | Network Address Translation — lets the VMs share the laptop's internet connection |
| NetBIOS | An older short name for the domain (`LAB`) used in logons like `LAB\ahrizwan` |
| NTFS | New Technology File System — Windows' disk format; its permissions control who can open a folder |
| OU | Organisational Unit — a folder inside AD for grouping users or computers (e.g. a department) |
| SMB | Server Message Block — the protocol Windows uses for shared folders |
| UNC path | Universal Naming Convention — a network path like `\\DC01\EngineeringShare` |
| VM | Virtual Machine — a computer running inside software on my laptop |

---

## Disclaimer

This is a learning lab built for practice. I will further tighten the security controls on **DC01** and **WS01** as the project continues.

---

### Repository layout

```
AD-Homelab/
├── README.md                  ← this page
├── AD-Homelab-Report.pdf      ← PDF copy of this page
├── images/                    ← screenshots used above
└── scripts/
    └── Create-ADUser.ps1
```

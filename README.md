# Clara SMS group chat

Clara is an SMS chat bot for distributing messages within a small user group. Users are managed via commands in text messages. New users must be activated by an administrator before they can text.

## Prerequisites

* Huawei HiLink capable LTE modem \
Tested with E3372-325 software version 3.0.2.61
* Docker or Podman installed
* usb-modeswitch installed

## Installation

### Preparing the E3372-325 modem

Follow these steps to enter HiLink mode.

https://www.draisberghof.de/usb_modeswitch/bb/viewtopic.php?t=3043&sid=54059b088d9a8d049c8558d5e9628e36

`/etc/udev/rules.d/40-huawei.rules`

```
ACTION!="add", GOTO="modeswitch_rules_end"
SUBSYSTEM!="usb", GOTO="modeswitch_rules_end"

# All known install partitions are on interface 0
ATTRS{bInterfaceNumber}!="00", GOTO="modeswitch_rules_end"

# only storage class devices are handled; negative
# filtering here would exclude some quirky devices
ATTRS{bDeviceClass}=="e0", GOTO="modeswitch_rules_begin"
ATTRS{bInterfaceClass}=="e0", GOTO="modeswitch_rules_begin"
GOTO="modeswitch_rules_end"

LABEL="modeswitch_rules_begin"
# Huawei E3372-325
ATTRS{idVendor}=="3566", ATTRS{idProduct}=="2001", RUN+="/sbin/usb_modeswitch -v 3566 -p 2001 -W -R -w 400"
ATTRS{idVendor}=="3566", ATTRS{idProduct}=="2001", RUN+="/sbin/usb_modeswitch -v 3566 -p 2001 -W -R"

LABEL="modeswitch_rules_end"
```

Insert SIM card and connect it to your computer.

Open your browser and enter http://192.168.8.1/

If your SIM card is protected by a PIN code, enter and save it.

### Building the container image

```
cd clara
docker build -t localhost/clara:latest .
```

### Preparing the data directory

The first administrator has to be entered manually in the recipients list. 

Replace +495555 with your phone number. This is **not** the number of your LTE modem.

```
cd clara/data
[ -f recipients.json ] || cat <<EOF >recipients.json
{
  "+495555": {
    "name": "YourName",
    "role": "admin"
  }
}
EOF
```

### Starting the chat bot

```
cd clara
docker run --rm -it --name clara \
  -v $PWD/src:/usr/src/app \
  -v $PWD/data:/usr/src/app/data \
  localhost/clara:latest
```

Exit with `Ctrl + c`

## User management

A user can have one of three roles.

* `nobody`: does not receives messages or notifications 
* `user`: receives group messages
* `admin`: receives group messages and can activate new users

### Adding a new recipient

1. The new recipient sends a join command with their desired user name. \
No reply is triggered to avoid DoS attacs.

`#join Mark`

2. The new recipient asks an administrator for activation. User name is required.

3. The administrator sends the activation command.

`#activate mark`

A reply message is send to the administrator and the recipient. \
The message contains the phone number of the recipient.

### Sending messages to the group chat

Every message not beginning with the hash sign (#) is replicated to every user and administrator except to yourself.

### Leaving the group chat

Every user can simply leave the group by sending a command to the chat bot.

`#leave`

To re-join the group an administrator must repeat the activation command. A join command is not required.


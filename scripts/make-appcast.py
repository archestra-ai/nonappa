#!/usr/bin/env python3
"""Write a single-version full-update feed hosted as a GitHub release asset."""
import base64
import re
import sys
import xml.etree.ElementTree as ET
from pathlib import Path


def make_appcast(archive, version, signature):
    if not re.fullmatch(r"\d+\.\d+\.\d+", version):
        raise ValueError("Invalid release version")
    if len(base64.b64decode(signature, validate=True)) != 64:
        raise ValueError("Invalid Ed25519 signature")
    archive = Path(archive)
    if archive.name != f"NoNappa-{version}-universal.zip":
        raise ValueError("Unexpected archive name")
    sparkle = "http://www.andymatuschak.org/xml-namespaces/sparkle"
    ET.register_namespace("sparkle", sparkle)
    rss = ET.Element("rss", version="2.0")
    channel = ET.SubElement(rss, "channel")
    ET.SubElement(channel, "title").text = "NoNappa"
    item = ET.SubElement(channel, "item")
    ET.SubElement(item, "title").text = f"NoNappa {version}"
    ET.SubElement(item, f"{{{sparkle}}}version").text = version
    ET.SubElement(item, f"{{{sparkle}}}shortVersionString").text = version
    ET.SubElement(item, f"{{{sparkle}}}minimumSystemVersion").text = "13.0.0"
    ET.SubElement(item, "description").text = "After updating, sleep controls may need administrator approval for this app build. Existing sleep sessions are preserved."
    ET.SubElement(item, "enclosure", {
        "url": f"https://github.com/archestra-ai/nonappa/releases/download/v{version}/{archive.name}",
        "length": str(archive.stat().st_size), "type": "application/octet-stream",
        f"{{{sparkle}}}edSignature": signature,
    })
    return ET.tostring(rss, encoding="utf-8", xml_declaration=True)


if __name__ == "__main__":
    archive, version, signature, destination = sys.argv[1:]
    Path(destination).write_bytes(make_appcast(archive, version, signature))

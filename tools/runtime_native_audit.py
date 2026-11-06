"""Read-only installed-JAR audit. It does not start the game or load a world."""
from pathlib import Path
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
GAME = Path(r"D:\steam\steamapps\common\ProjectZomboid")
JAVAP = Path(r"E:\code\java-1.8.0-openjdk-1.8.0.392-1.b08.redhat.windows.x86_64\bin\javap.exe")
OUT = ROOT / "tests"


def bytecode(name):
    result = subprocess.run([str(JAVAP), "-p", "-c", "-classpath", str(GAME / "projectzomboid.jar"), name], capture_output=True, check=True)
    return result.stdout.decode("utf-8", errors="replace")


def method(code, signature):
    start = code.index(signature)
    end_match = re.search(r"\n  (?:public|private|protected) ", code[start + len(signature):])
    return code[start:] if not end_match else code[start:start + len(signature) + end_match.start()]


def main():
    food = bytecode("zombie.inventory.types.Food")
    container = bytecode("zombie.inventory.ItemContainer")
    schedule = bytecode("zombie.gameStates.IngameState")
    generator = bytecode("zombie.iso.objects.IsoGenerator")
    cell = bytecode("zombie.iso.IsoCell")
    player = bytecode("zombie.characters.IsoPlayer")
    character = bytecode("zombie.characters.IsoGameCharacter")
    save = bytecode("zombie.GameWindow")
    for label, text in [("food", food), ("container", container), ("schedule", schedule), ("generator", generator), ("cell", cell), ("player", player), ("character", character), ("save", save)]:
        (OUT / ("runtime_" + label + "_bytecode.txt")).write_text(text, encoding="utf-8")
    findings = []

    def verify(condition, label):
        if not condition:
            raise AssertionError(label)
        findings.append(label)

    rot = method(food, "private void updateRotting(zombie.inventory.ItemContainer);")
    rotten = method(food, "public boolean isRotten();")
    update = method(food, "public void update();")
    powered = method(container, "public boolean isPowered();")
    internal = method(schedule, "private zombie.gameStates.GameStateMachine$StateAction updateInternal();")
    verify("Method updateRotting:" in update, "native Food.update directly calls private updateRotting")
    verify(rot.index("Field replaceOnRotten:") < rot.index("Method isRotten:") < rot.index("Method zombie/inventory/InventoryItemFactory.CreateItem:"), "native rot replacement follows updateAge and isRotten")
    verify("Field zombie/SandboxOptions.daysForRottenFoodRemoval:" in rot and "Method destroyThisItem:" in rot, "native rotten-removal setting can delete an existing food")
    verify("Field age:F" in rotten and "Field offAgeMax:I" in rotten and "Field rotten:Z" not in rotten, "isRotten compares actual age against threshold rather than the legacy boolean flag")
    verify("Method zombie/iso/IsoObject.checkObjectPowered:" in powered and "getWorldAgeHours" not in powered, "isPowered queries current object power and contains no power-history lookup")
    verify(internal.index("String OnTickEvenPaused") < internal.index("Method zombie/iso/IsoWorld.update:") < internal.index("Method UpdateStuff:") < internal.index("Method onTick:"), "installed frame order is pre-event, world update, GameTime helper, post-event")
    verify(internal.index("String OnTickEvenPaused") < internal.index("Field zombie/core/Core.exiting:") < internal.index("Method zombie/GameWindow.save:"), "pre-event runs before the exit-save branch")
    verify("Field lastHour:I" in generator and "Field activated:Z" in generator and "Field fuel:F" in generator, "generator maintains current activation, fuel, and last processed hour")
    cell_update = method(cell, "private void updateInternal();")
    player1 = method(player, "private void updateInternal1();")
    player2 = method(player, "private boolean updateInternal2();")
    character_update = method(character, "private void updateInternal();")
    save_body = method(save, "public static void save(boolean) throws java.io.IOException;")
    verify(cell_update.index("Method ProcessItems:") < cell_update.index("Method ProcessObjects:"), "SP cell processes native items before moving objects and players")
    verify(player1.index("Method updateInternal2:") < player1.rindex("Method zombie/characters/IsoLivingCharacter.update:") and "String OnPlayerUpdate" in player2, "OnPlayerUpdate can restore transient food shields before the normal player superclass update")
    verify("Method zombie/characters/CharacterTimedActions/BaseAction.update:" in character_update and "Method zombie/characters/CharacterTimedActions/BaseAction.perform:" in character_update, "player superclass update owns timed-action updates and completion")
    verify(save_body.rindex("String OnSave") < save_body.index("Method zombie/iso/IsoCell.save:"), "OnSave fires before the current cell is serialized")
    result = {
        "result": "PASS",
        "checks": findings,
        "game_jar_sha256": hashlib.sha256((GAME / "projectzomboid.jar").read_bytes()).hexdigest(),
        "game_started": False,
        "source": "javap -p -c against the current installed game JAR",
        "limits": "Static control-flow audit. It does not validate world streaming, UI rendering, or native hook interoperation in a game session.",
    }
    (OUT / "runtime_native_audit.json").write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(json.dumps({"result": result["result"], "checks": len(findings), "game_started": False}))


if __name__ == "__main__":
    main()

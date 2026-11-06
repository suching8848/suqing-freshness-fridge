import java.lang.reflect.Field;
import java.lang.reflect.Method;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Paths;
import java.util.Arrays;
import java.util.LinkedHashMap;
import java.util.Map;
import sun.misc.Unsafe;

/** A method-level native probe. It never constructs an IsoWorld or starts a client. */
public class runtime_NativeShieldProbe {
    static Field field(Class<?> type, String name) throws Exception {
        for (Class<?> current = type; current != null; current = current.getSuperclass()) {
            try {
                Field result = current.getDeclaredField(name);
                result.setAccessible(true);
                return result;
            } catch (NoSuchFieldException ignored) { }
        }
        throw new NoSuchFieldException(name);
    }

    static void set(Object object, String name, Object value) throws Exception {
        field(object.getClass(), name).set(object, value);
    }

    static int assertions;

    static void check(boolean result, String description) {
        assertions++;
        if (!result) throw new AssertionError(description);
    }

    public static void main(String[] args) throws Exception {
        Field unsafeField = Unsafe.class.getDeclaredField("theUnsafe");
        unsafeField.setAccessible(true);
        Unsafe unsafe = (Unsafe) unsafeField.get(null);

        Class<?> fs = Class.forName("zombie.ZomboidFileSystem");
        fs.getMethod("init").invoke(fs.getField("instance").get(null));
        for (String name : new String[] {"RandStandard", "RandLua"}) {
            Class<?> random = Class.forName("zombie.core.random." + name);
            random.getMethod("init").invoke(random.getField("INSTANCE").get(null));
        }
        Class.forName("zombie.Lua.LuaManager").getMethod("init").invoke(null);
        Class<?> timeClass = Class.forName("zombie.GameTime");
        Object time = timeClass.getConstructor().newInstance();
        timeClass.getMethod("setInstance", timeClass).invoke(null, time);
        set(time, "timeOfDay", 12.0f);
        float now = ((Double) timeClass.getMethod("getWorldAgeHours").invoke(time)).floatValue();

        Class<?> foodClass = Class.forName("zombie.inventory.types.Food");
        Class<?> containerClass = Class.forName("zombie.inventory.ItemContainer");
        Object food = unsafe.allocateInstance(foodClass);
        Object container = containerClass.getConstructor().newInstance();
        Class<?> objectClass = Class.forName("zombie.iso.IsoObject");
        Class<?> spriteClass = Class.forName("zombie.iso.sprite.IsoSprite");
        Object object = objectClass.getConstructor().newInstance();
        Object sprite = unsafe.allocateInstance(spriteClass);
        set(sprite, "name", "suqing_freshness_fridge_01_0");
        set(object, "sprite", sprite);
        objectClass.getMethod("setContainer", containerClass).invoke(object, container);
        set(container, "parent", object);
        set(container, "type", "fridge");
        set(food, "container", container);
        set(food, "offAge", 5);
        set(food, "offAgeMax", 10);
        set(food, "age", 15.0f);
        set(food, "lastAged", now);
        set(food, "heat", 0.2f);
        set(food, "hungChange", -0.15f);
        set(food, "baseHunger", -0.30f);
        set(food, "calories", 168.0f);
        set(food, "cooked", true);
        set(food, "isTainted", true);
        set(food, "poisonPower", 12);
        set(food, "replaceOnRotten", "NoSuchReplacementForMethodProbe");
        set(food, "module", "Base");
        set(food, "type", "Apple");
        set(food, "fullType", "Base.Apple");
        set(food, "id", 303);

        Map<String, Object> unchanged = new LinkedHashMap<String, Object>();
        for (String name : new String[] {"offAge", "offAgeMax", "hungChange", "baseHunger", "calories", "cooked", "isTainted", "poisonPower", "replaceOnRotten", "container"}) {
            unchanged.put(name, field(foodClass, name).get(food));
        }
        Method rotten = foodClass.getMethod("isRotten");
        Method age = foodClass.getMethod("setAge", float.class);
        Method nativeRot = foodClass.getDeclaredMethod("updateRotting", containerClass);
        nativeRot.setAccessible(true);

        Class<?> sandboxClass = Class.forName("zombie.SandboxOptions");
        Object sandbox = sandboxClass.getField("instance").get(null);
        Object removal = field(sandboxClass, "daysForRottenFoodRemoval").get(sandbox);
        removal.getClass().getMethod("setValue", int.class).invoke(removal, 0);

        check(Boolean.TRUE.equals(rotten.invoke(food)), "native food starts rotten");
        for (int pass = 0; pass < 120; pass++) {
            age.invoke(food, 9.999f);
            nativeRot.invoke(food, container);
            check(!Boolean.TRUE.equals(rotten.invoke(food)), "native pre-world guard stays below rotten threshold");
            age.invoke(food, 15.0f);
            check(Boolean.TRUE.equals(rotten.invoke(food)), "native post-world restore retains rotten state");
        }
        for (Map.Entry<String, Object> entry : unchanged.entrySet()) {
            check(entry.getValue().equals(field(foodClass, entry.getKey()).get(food)), "unrelated food field preserved: " + entry.getKey());
        }
        check(((Float) foodClass.getMethod("getAge").invoke(food)).floatValue() == 15.0f, "logical native food age restored exactly");
        for (int capacity : new int[] {50, 200, 1000}) {
            containerClass.getMethod("setCapacity", int.class).invoke(container, capacity);
            check(((Integer) field(containerClass, "capacity").get(container)).intValue() == capacity,
                    "native ItemContainer raw capacity field stores: " + capacity);
            check(((Integer) containerClass.getMethod("getCapacity").invoke(container)).intValue() == Math.min(capacity, 100),
                    "native ItemContainer getter retains the 100 world-container limit: " + capacity);
        }
        Method nativeAdd = containerClass.getMethod("AddItem", Class.forName("zombie.inventory.InventoryItem"));
        for (int index = 0; index < 101; index++) {
            Object weightedFood = unsafe.allocateInstance(Class.forName("zombie.inventory.InventoryItem"));
            set(weightedFood, "id", 1000 + index);
            set(weightedFood, "module", "Base");
            set(weightedFood, "type", "Apple");
            set(weightedFood, "fullType", "Base.Apple");
            set(weightedFood, "name", "Audit item");
            set(weightedFood, "actualWeight", 1.0f);
            nativeAdd.invoke(container, weightedFood);
        }
        check(((Float) containerClass.getMethod("getCapacityWeight").invoke(container)).floatValue() == 101.0f,
                "native AddItem accepts actual contents beyond its getter's world-container limit");
        check(((java.util.List<?>) containerClass.getMethod("getItems").invoke(container)).size() == 101,
                "all 101 native weighted items remain in the native container");
        Object source = containerClass.getConstructor().newInstance();
        set(source, "type", "inventory");
        Object incoming = unsafe.allocateInstance(Class.forName("zombie.inventory.InventoryItem"));
        set(incoming, "id", 9999);
        set(incoming, "module", "Base");
        set(incoming, "type", "AuditIncoming");
        set(incoming, "fullType", "Base.AuditIncoming");
        set(incoming, "name", "Audit incoming item");
        set(incoming, "actualWeight", 5.0f);
        nativeAdd.invoke(source, incoming);
        Object otherContainer = containerClass.getConstructor().newInstance();
        Object otherObject = objectClass.getConstructor().newInstance();
        Object otherSprite = unsafe.allocateInstance(spriteClass);
        set(otherSprite, "name", "appliances_refrigeration_01_25");
        set(otherObject, "sprite", otherSprite);
        objectClass.getMethod("setContainer", containerClass).invoke(otherObject, otherContainer);
        set(otherContainer, "parent", otherObject);
        set(otherContainer, "type", "fridge");
        set(otherContainer, "capacity", 1000);
        System.out.println("NATIVE_SHIELD passes=120 assertions=" + assertions + " game_started=false world_created=false PASS");
        if (args.length > 0) {
            // Prepare method-level display coverage only after the legacy native
            // guard/capacity checks above, leaving their original 120-pass proof intact.
            set(food, "scriptItem", Class.forName("zombie.scripting.objects.Item").getConstructor().newInstance());
            set(food, "name", "Native display food");
            set(food, "stressChange", -0.12f);
            set(food, "endChange", 0.15f);
            set(food, "unhappyChange", 2.0f);
            set(food, "boredomChange", 3.0f);
            set(food, "carbohydrates", 17.0f);
            set(food, "lipids", 8.0f);
            set(food, "proteins", 4.0f);
            for (String[] text : new String[][] {
                    {"freshString", "Fresh"}, {"staleString", "Stale"}, {"offString", "Rotten"},
                    {"cookedString", "Cooked"}, {"unCookedString", "Uncooked"}, {"burntString", "Burnt"},
                    {"frozenString", "Frozen"}, {"grilledString", "Grilled"}, {"toastedString", "Toasted"}}) {
                set(food, text[0], text[1]);
            }
            Class<?> translator = Class.forName("zombie.core.Translator");
            ((Map<?,?>) field(translator, "ui").get(null)).clear();
            @SuppressWarnings("unchecked")
            Map<String,String> displayTranslations = (Map<String,String>) field(translator, "igui").get(null);
            displayTranslations.clear();
            displayTranslations.put("IGUI_FoodNaming", "%2 (%1)");
            Class<?> luaManager = Class.forName("zombie.Lua.LuaManager");
            Object environment = luaManager.getField("env").get(null);
            Object thread = luaManager.getField("thread").get(null);
            Class<?> tableInterface = Class.forName("se.krka.kahlua.vm.KahluaTable");
            Method put = tableInterface.getMethod("rawset", Object.class, Object.class);
            put.invoke(environment, "ProbeFood", food);
            put.invoke(environment, "ProbeFridge", container);
            put.invoke(environment, "ProbeObject", object);
            put.invoke(environment, "ProbeSource", source);
            put.invoke(environment, "ProbeIncoming", incoming);
            put.invoke(environment, "ProbeOtherFridge", otherContainer);
            put.invoke(environment, "ProbeTime", time);
            put.invoke(environment, "ProbeNativeRemoval", removal);
            Class<?> javaFunction = Class.forName("se.krka.kahlua.vm.JavaFunction");
            Object nativeRotCallback = java.lang.reflect.Proxy.newProxyInstance(javaFunction.getClassLoader(),
                    new Class<?>[] {javaFunction}, (proxy, method, callbackArgs) -> {
                        if (method.getName().equals("call")) {
                            nativeRot.invoke(food, container);
                            return Integer.valueOf(0);
                        }
                        if (method.getName().equals("toString")) return "Native Food.updateRotting probe";
                        if (method.getName().equals("hashCode")) return Integer.valueOf(System.identityHashCode(proxy));
                        if (method.getName().equals("equals")) return Boolean.valueOf(proxy == callbackArgs[0]);
                        throw new UnsupportedOperationException(method.getName());
                    });
            put.invoke(environment, "ProbeNativeRot", nativeRotCallback);
            Method compile = Class.forName("se.krka.kahlua.luaj.compiler.LuaCompiler")
                    .getMethod("loadstring", String.class, String.class, tableInterface);
            Method call = thread.getClass().getMethod("pcall", Object.class, Object[].class);
            for (String filename : args) {
                String luaSource = new String(Files.readAllBytes(Paths.get(filename)), StandardCharsets.UTF_8);
                Object closure = compile.invoke(null, luaSource, filename, environment);
                Object[] result = (Object[]) call.invoke(thread, closure, new Object[0]);
                System.out.println(filename + ": " + Arrays.toString(result));
                if (!Boolean.TRUE.equals(result[0])) throw new AssertionError("native Core regression failed: " + Arrays.toString(result));
            }
        }
    }
}

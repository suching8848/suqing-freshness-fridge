import java.lang.reflect.*;
import java.nio.file.*;
import java.nio.charset.StandardCharsets;
import java.util.*;
import java.util.function.Function;

/** Offline component parsing only; never starts the game or loads a save. */
public class building_NativeAudit {
    static int assertions;
    static void check(boolean condition, String label) {
        assertions++;
        if (!condition) throw new AssertionError(label);
    }
    static Field field(Class<?> type, String name) throws Exception {
        for (Class<?> c=type; c!=null; c=c.getSuperclass()) {
            try { Field f=c.getDeclaredField(name); f.setAccessible(true); return f; }
            catch (NoSuchFieldException ignored) { }
        }
        throw new NoSuchFieldException(name);
    }
    static Object block(Path path) throws Exception {
        Class<?> p=Class.forName("zombie.scripting.ScriptParser");
        String text=new String(Files.readAllBytes(path), StandardCharsets.UTF_8);
        text=(String)p.getMethod("stripComments",String.class).invoke(null,text);
        return p.getMethod("parse",String.class).invoke(null,text);
    }
    static Object first(Object block) throws Exception {
        return ((List<?>)block.getClass().getField("children").get(block)).get(0);
    }
    public static void main(String[] args) throws Exception {
        Path scripts=Paths.get(args[0]);
        Class<?> manager=Class.forName("zombie.scripting.ScriptManager");
        field(manager,"currentLoadFileMod").set(null,"SuQingFreshnessFridge");
        field(manager,"currentLoadFileAbsPath").set(null,scripts.resolve("SuQingFreshnessFridge_Building.txt").toString());
        field(manager,"currentLoadFileName").set(null,"SuQingFreshnessFridge_Building.txt");
        Object root=block(scripts.resolve("SuQingFreshnessFridge_Building.txt"));
        Object moduleBlock=first(root), entityBlock=first(moduleBlock);
        Class<?> blockClass=root.getClass();
        check("SuQingFreshnessFridge".equals(blockClass.getField("id").get(moduleBlock)),"independent module");
        check("FreshnessFridge".equals(blockClass.getField("id").get(entityBlock)),"one named entity");
        Class<?> moduleClass=Class.forName("zombie.scripting.objects.ScriptModule");
        Object module=moduleClass.getConstructor().newInstance();
        moduleClass.getField("name").set(module,"SuQingFreshnessFridge");
        Class<?> entityClass=Class.forName("zombie.scripting.entity.GameEntityScript");
        Object entity=entityClass.getConstructor().newInstance();
        entityClass.getMethod("setModule",moduleClass).invoke(entity,module);
        field(entityClass,"name").set(entity,"FreshnessFridge");
        field(entityClass,"scriptObjectName").set(entity,"FreshnessFridge");
        for (Object child:(List<?>)blockClass.getField("children").get(entityBlock)) {
            entityClass.getMethod("LoadComponentBlock",blockClass).invoke(entity,child);
        }
        Class<?> componentClass=Class.forName("zombie.entity.ComponentType");
        Object craftType=componentClass.getMethod("valueOf",String.class).invoke(null,"CraftRecipe");
        Object spriteType=componentClass.getMethod("valueOf",String.class).invoke(null,"SpriteConfig");
        Object craft=entityClass.getMethod("getComponentScriptFor",componentClass).invoke(entity,craftType);
        Object sprite=entityClass.getMethod("getComponentScriptFor",componentClass).invoke(entity,spriteType);
        Object recipe=craft.getClass().getMethod("getCraftRecipe").invoke(craft);
        Class<?> rc=recipe.getClass();
        check("SuQingFreshnessFridge".equals(rc.getMethod("getCategory").invoke(recipe)),"native menu category");
        check("IGUI_SuQingFreshnessFridge_Name".equals(craft.getClass().getMethod("getBuildCategory").invoke(craft)),"native context-build category uses dedicated translated name");
        check(((List<?>)rc.getMethod("getTags").invoke(recipe)).contains("Welding"),"native welding tag retained");
        Class<?> tagClass=Class.forName("zombie.scripting.objects.CraftRecipeTag");
        check((Boolean)rc.getMethod("hasTag",tagClass).invoke(recipe,tagClass.getField("WELDING").get(null)),"native welding enum predicate unchanged");
        check(((Integer)rc.getMethod("getRequiredSkillCount").invoke(recipe))==0,"no added skill requirement");
        check(((Integer)rc.getMethod("getOutputCount").invoke(recipe))==0,"construction has no item output/duplication path");
        List<?> inputs=(List<?>)rc.getMethod("getInputs").invoke(recipe);
        check(inputs.size()==9,"two kept tools, one fuel row, six material rows");
        Class<?> input=Class.forName("zombie.scripting.entity.components.crafting.InputScript");
        for (int i=0;i<2;i++) check((Boolean)input.getMethod("isKeep").invoke(inputs.get(i)),"tool kept "+i);
        Object fuel=inputs.get(2);
        check(((Float)input.getMethod("getAmount").invoke(fuel))==1f,"exactly one torch fuel use");
        check(!(Boolean)input.getMethod("isItemCount").invoke(fuel),"fuel consumes use rather than tool count");
        check(((List<?>)input.getMethod("getItems").invoke(fuel)).contains("Base.BlowTorch"),"native blowtorch fuel");
        String[] ids={"Base.SmallSheetMetal","Base.ElectricWire","Base.AlarmClock2",null,"Base.Pocketwatch",null};
        int[] counts={4,2,1,1,1,1};
        for (int i=3;i<inputs.size();i++) {
            Object row=inputs.get(i);
            check(((Float)input.getMethod("getAmount").invoke(row))==counts[i-3],"required count "+i);
            check((Boolean)input.getMethod("isItemCount").invoke(row),"whole material objects "+i);
            check((Boolean)input.getMethod("isDestroy").invoke(row),"material consumed "+i);
            if (ids[i-3]!=null) check(((List<?>)input.getMethod("getItems").invoke(row)).contains(ids[i-3]),"exact material ID "+i);
        }
        Set<?> digital=new HashSet<Object>((List<?>)input.getMethod("getItems").invoke(inputs.get(6)));
        Set<?> classic=new HashSet<Object>((List<?>)input.getMethod("getItems").invoke(inputs.get(8)));
        check(digital.size()==6,"six digital colour/side variants");
        check(classic.size()==8,"eight classic colour/side variants");
        check(Collections.disjoint(digital,classic),"one physical watch cannot satisfy both rows");
        for (Object id:digital) check(id.toString().contains("_Digital"),"digital family only");
        for (Object id:classic) check(id.toString().contains("_Classic"),"classic family only");
        check("SuQingFreshnessFridge.Building.OnCreate".equals(sprite.getClass().getMethod("getOnCreate").invoke(sprite)),"construction callback");
        check(((Integer)sprite.getClass().getMethod("getHealth").invoke(sprite))==300,"fixed health independent of skill");
        Set<String> directions=new HashSet<String>();
        Set<String> sprites=new HashSet<String>();
        for (int i=0;i<4;i++) {
            Object face=sprite.getClass().getMethod("getFace",int.class).invoke(sprite,i);
            check(face!=null,"face exists "+i);
            directions.add(face.getClass().getMethod("getFaceName").invoke(face).toString().toUpperCase());
            Object layer=face.getClass().getMethod("getLayer",int.class).invoke(face,0);
            Object row=layer.getClass().getMethod("getRow",int.class).invoke(layer,0);
            Object tile=row.getClass().getMethod("getTile",int.class).invoke(row,0);
            sprites.add((String)tile.getClass().getMethod("getTileName").invoke(tile));
            check(((Integer)face.getClass().getMethod("getTotalWidth").invoke(face))==1,"single tile width");
            check(((Integer)face.getClass().getMethod("getTotalHeight").invoke(face))==1,"single tile depth");
        }
        check(directions.equals(new HashSet<String>(Arrays.asList("S","E","N","W"))),"four compass facings");
        for (int i=0;i<4;i++) check(sprites.contains("suqing_freshness_fridge_01_"+i),"independent tile "+i);
        for (String name:Arrays.asList("SuQingFreshnessFridge_Items.txt","SuQingFreshnessFridge_Xui.txt")) {
            check(first(block(scripts.resolve(name)))!=null,"native block parse "+name);
        }
        Object itemBlock=first(first(block(scripts.resolve("SuQingFreshnessFridge_Items.txt"))));
        Class<?> itemClass=Class.forName("zombie.scripting.objects.Item");
        Object item=itemClass.getConstructor().newInstance();
        itemClass.getMethod("setModule",moduleClass).invoke(item,module);
        // Icon parsing immediately requests a GL-backed Texture. Check its
        // grammar/value, then omit only that value from this headless probe.
        // Rendering and the actual PNG are validated by the asset audit.
        Object iconValue=blockClass.getMethod("getValue",String.class).invoke(itemBlock,"Icon");
        check("SuQingFreshnessFridge".equals(iconValue.getClass().getMethod("getValue").invoke(iconValue).toString().trim()),"movable icon identifier");
        ((List<?>)blockClass.getField("values").get(itemBlock)).remove(iconValue);
        ((List<?>)blockClass.getField("elements").get(itemBlock)).remove(iconValue);
        StringBuilder itemText=new StringBuilder();
        blockClass.getMethod("prettyPrint",int.class,StringBuilder.class).invoke(itemBlock,0,itemText);
        itemClass.getMethod("Load",String.class,String.class).invoke(item,"Mov_FreshnessFridge",itemText.toString());
        check("suqing_freshness_fridge_01_0".equals(itemClass.getMethod("getWorldObjectSprite").invoke(item)),"native movable item points at independent tile");
        Object xuiBlock=first(first(block(scripts.resolve("SuQingFreshnessFridge_Xui.txt"))));
        Object styleBlock=first(xuiBlock);
        Class<?> xuiClass=Class.forName("zombie.scripting.objects.XuiSkinScript");
        Object xui=xuiClass.getConstructor().newInstance();
        Method loadStyle=xuiClass.getDeclaredMethod("LoadEntityBlock",blockClass);
        loadStyle.setAccessible(true);loadStyle.invoke(xui,styleBlock);
        Map<?,?> styles=(Map<?,?>)xuiClass.getMethod("getEntityUiScriptMap").invoke(xui);
        Object style=styles.get("ES_SuQingFreshnessFridge");
        check(style!=null,"native XUI entity style parsed");
        check("IGUI_SuQingFreshnessFridge_Name".equals(style.getClass().getMethod("getDisplayName").invoke(style)),"native XUI translated name key");
        check("IGUI_SuQingFreshnessFridge_BuildDescription".equals(style.getClass().getMethod("getBuildDescription").invoke(style)),"native XUI translated build description");
        // Load the actual mod JSON through the game's own Translator reader,
        // then exercise the same lookup functions used by the B42 UI.
        Class<?> translator=Class.forName("zombie.core.Translator");
        Class<?> languageClass=Class.forName("zombie.core.Language");
        Constructor<?> languageCtor=languageClass.getDeclaredConstructor(String.class,String.class,String.class,boolean.class);
        languageCtor.setAccessible(true);
        Method fill=translator.getDeclaredMethod("tryFillMapFromFile",String.class,String.class,Map.class,languageClass,Function.class);
        fill.setAccessible(true);
        String[] files={"IG_UI","Recipes","ItemName","Moveables"};
        String[] maps={"igui","recipe","itemName","moveables"};
        int translationStart=assertions;
        for (String languageName:Arrays.asList("CN","CH","EN")) {
            Object language=languageCtor.newInstance(languageName,languageName,"EN",false);
            translator.getField("language").set(null,language);
            for (int i=0;i<files.length;i++) {
                Map<?,?> map=(Map<?,?>)field(translator,maps[i]).get(null);
                map.clear();
                fill.invoke(null,scripts.getParent().getParent().toString(),files[i],map,language,Function.identity());
                check(!map.isEmpty(),"native JSON reader loaded "+languageName+"/"+files[i]);
            }
            String expected=languageName.equals("EN")?"SuQing's Freshness Fridge":"蘇清的返鲜冰箱";
            Map<String,String> modMetadata=new HashMap<>();
            fill.invoke(null,scripts.getParent().getParent().toString(),"Mod",modMetadata,language,Function.identity());
            check(expected.equals(modMetadata.get("name")),"native mod-selector name "+languageName);
            check(modMetadata.containsKey("description") && modMetadata.get("description").length()>100,"native mod-selector description "+languageName);
            Method getText=translator.getMethod("getText",String.class,Object[].class);
            check(expected.equals(getText.invoke(null,"IGUI_SuQingFreshnessFridge_Name",new Object[0])),"native entity/context name "+languageName);
            check(expected.equals(getText.invoke(null,"IGUI_CraftingCategories_SuQingFreshnessFridge",new Object[0])),"native B42 build category name "+languageName);
            check(expected.equals(translator.getMethod("getRecipeName",String.class).invoke(null,"FreshnessFridge")),"native bare recipe key "+languageName);
            check(expected.equals(translator.getMethod("getItemNameFromFullType",String.class).invoke(null,"SuQingFreshnessFridge.Mov_FreshnessFridge")),"native bare full item ID "+languageName);
            check(expected.equals(translator.getMethod("getMoveableDisplayName",String.class).invoke(null,"SuQing FreshnessFridge")),"native movable name "+languageName);
            check(translator.getMethod("getTextOrNull",String.class,Object[].class).invoke(null,"Recipes_SuQingFreshnessFridge",new Object[0])==null,"Recipes_ is not a getText namespace "+languageName);
        }
        System.out.println("BUILDING_TRANSLATOR assertions="+(assertions-translationStart)+" failures=0");
        System.out.println("BUILDING_NATIVE assertions="+assertions+" failures=0");
    }
}

import java.lang.reflect.*;
import java.nio.file.*;
import java.util.*;

// Offline only: current installed Viewpoint parser/rotation calls, no renderer.
public class integration_viewpoint {
    static Object field(Object o,String n)throws Exception{
        Field f=o.getClass().getDeclaredField(n);f.setAccessible(true);return f.get(o);
    }
    public static void main(String[]args)throws Exception{
        Class<?> reader=Class.forName("viewpoint.packs.ObjReader");
        Method parse=reader.getDeclaredMethod("parse",List.class);parse.setAccessible(true);
        Object mesh=parse.invoke(null,Arrays.asList("v 0 1 0","v 1 1 0","v 0 1 1","vt 0 0","vt 1 0","vt 0 1","f 1/1 2/2 3/3"));
        Method values=mesh.getClass().getDeclaredMethod("vertices");values.setAccessible(true);
        float[]points=(float[])values.invoke(mesh);
        System.out.println("source (0,1,0) parses as "+Arrays.toString(Arrays.copyOfRange(points,0,8)));
        Class<?> packModel=Class.forName("viewpoint.render.PackModel");
        Class<?> binding=Class.forName("viewpoint.packs.PackBind");
        Constructor<?> ctor=binding.getConstructor(packModel,float.class,float.class,float.class,float.class,float.class);
        Method place=binding.getMethod("place",float.class,float.class,float.class,boolean.class,float[].class);
        Class<?> manifest=Class.forName("viewpoint.packs.PackManifest");
        Method pm=manifest.getDeclaredMethod("parse",List.class);pm.setAccessible(true);
        Object data=pm.invoke(null,Files.readAllLines(Paths.get(args[0])));
        List<?>errors=(List<?>)field(data,"errors");
        if(!errors.isEmpty())throw new AssertionError("manifest errors: "+errors);
        Map<?,?>binds=(Map<?,?>)field(data,"binds");
        int[]degrees={0,-90,180,90};
        String[]facings={"S","E","N","W"};
        float[][]expected={{0,0,-1},{-1,0,0},{0,0,1},{1,0,0}};
        for(int i=0;i<4;i++){
            Object entry=binds.get("suqing_freshness_fridge_01_"+i);
            if(entry==null)throw new AssertionError("missing sprite binding "+i);
            float actual=((Float)field(entry,"degrees")).floatValue();
            if(actual!=degrees[i])throw new AssertionError("incorrect manifest facing "+facings[i]);
            Object bound=ctor.newInstance(null,actual,0f,0f,0f,1f);
            float[]out=new float[3];
            place.invoke(bound,points[0],points[1],points[2],true,out);
            for(int j=0;j<3;j++)if(Math.abs(out[j]-expected[i][j])>0.00001f)throw new AssertionError("renderer-space facing "+facings[i]);
            System.out.println("PASS "+facings[i]+" bind "+degrees[i]+" -> "+Arrays.toString(out));
        }
        System.out.println("manifest errors="+errors);
        System.out.println("model keys="+((Map<?,?>)field(data,"models")).keySet());
        System.out.println("sprite keys="+((Map<?,?>)field(data,"binds")).keySet());
    }
}

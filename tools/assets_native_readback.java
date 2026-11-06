import java.io.*;
import java.lang.reflect.*;
import java.nio.file.*;
import java.util.*;

// Pure parser calls only. No game bootstrap, game state, renderer, OpenGL or UI.
public class assets_native_readback {
    static Object call(Class<?> type,String name,Class<?>[] signature,Object... args) throws Exception {
        Method method=type.getDeclaredMethod(name,signature);method.setAccessible(true);
        return method.invoke(null,args);
    }
    static int readInt(Class<?> type,InputStream in) throws Exception {
        return (Integer)call(type,"readInt",new Class<?>[]{InputStream.class},in);
    }
    public static void main(String[] args) throws Exception {
        Class<?> tp=Class.forName("zombie.core.textures.TexturePackPage");
        try(InputStream in=new BufferedInputStream(new FileInputStream(args[0]))) {
            byte[] magic=new byte[4];if(in.read(magic)!=4 || !Arrays.equals(magic,new byte[]{80,90,80,75}))throw new IOException("pack magic");
            int version=readInt(tp,in),pages=readInt(tp,in);
            if(version!=1||pages!=1)throw new IOException("pack version/pages");
            String page=(String)call(tp,"ReadString",new Class<?>[]{InputStream.class},in);
            int count=readInt(tp,in),alpha=readInt(tp,in);
            if(count!=4||alpha!=1)throw new IOException("subtexture count/alpha");
            for(int i=0;i<count;i++) {
                String name=(String)call(tp,"ReadString",new Class<?>[]{InputStream.class},in);
                if(!name.equals("suqing_freshness_fridge_01_"+i))throw new IOException("sprite name");
                int[] want={i*128,0,128,256,0,0,128,256};
                for(int j=0;j<8;j++)if(readInt(tp,in)!=want[j])throw new IOException("sprite bounds");
            }
            int len=readInt(tp,in);byte[] png=new byte[len];int pos=0,n;
            while(pos<len && (n=in.read(png,pos,len-pos))!=-1)pos+=n;
            if(pos!=len||in.read()!=-1)throw new IOException("PNG byte length/EOF");
            java.awt.image.BufferedImage image=javax.imageio.ImageIO.read(new ByteArrayInputStream(png));
            if(image==null||image.getWidth()!=512||image.getHeight()!=256)throw new IOException("PNG decode");
            System.out.println("PASS current PZ TexturePackPage integer/string readers: "+page+", four full RGBA sprite rectangles, PNG "+len+" bytes.");
        }
        Class<?> reader=Class.forName("viewpoint.packs.ObjReader");
        Object mesh=call(reader,"parse",new Class<?>[]{List.class},Files.readAllLines(Paths.get(args[1])));
        Method vm=mesh.getClass().getDeclaredMethod("vertices");vm.setAccessible(true);
        Method im=mesh.getClass().getDeclaredMethod("indices");im.setAccessible(true);
        Method mm=mesh.getClass().getDeclaredMethod("mtllib");mm.setAccessible(true);
        float[] vertices=(float[])vm.invoke(mesh);int[] indices=(int[])im.invoke(mesh);
        if(vertices.length==0||indices.length!=562*3)throw new IOException("OBJ parser geometry counts");
        if(!"fridge.mtl".equals(mm.invoke(mesh)))throw new IOException("OBJ material resolution");
        for(float f:vertices)if(!Float.isFinite(f))throw new IOException("nonfinite parsed vertex");
        System.out.println("PASS current installed Viewpoint ObjReader: "+vertices.length+" vertex components, "+indices.length+" indices; fridge.mtl.");
        System.out.println("Scope: offline parser calls. No engine/world initialization, GL context, running game connection, or in-game acceptance.");
    }
}

using System;
using System.IO;
using System.Runtime.InteropServices;

// Windows Shell 回收站接口；回调拒绝任何未标记为回收的删除。
[ComImport, Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IShellItem {
 void BindToHandler(IntPtr a,ref Guid b,ref Guid c,out IntPtr d);
 void GetParent(out IShellItem p);
 void GetDisplayName(uint kind,out IntPtr name);
 void GetAttributes(uint mask,out uint attrs);
 void Compare(IShellItem other,uint hint,out int result);
}
[ComImport, Guid("947AAB5F-0A5C-4C13-B4D6-4BF7836FC9F8"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IFileOperation {
 void Advise(IProgressSink sink,out uint cookie); void Unadvise(uint cookie);
 void SetOperationFlags(uint flags); void SetProgressMessage([MarshalAs(UnmanagedType.LPWStr)]string message);
 void SetProgressDialog(IntPtr dialog); void SetProperties(IntPtr properties); void SetOwnerWindow(uint hwnd);
 void ApplyPropertiesToItem(IShellItem item); void ApplyPropertiesToItems(IntPtr items);
 void RenameItem(IShellItem item,[MarshalAs(UnmanagedType.LPWStr)]string name,IProgressSink sink); void RenameItems(IntPtr items,[MarshalAs(UnmanagedType.LPWStr)]string name);
 void MoveItem(IShellItem item,IShellItem dest,[MarshalAs(UnmanagedType.LPWStr)]string name,IProgressSink sink); void MoveItems(IntPtr items,IShellItem dest);
 void CopyItem(IShellItem item,IShellItem dest,[MarshalAs(UnmanagedType.LPWStr)]string name,IProgressSink sink); void CopyItems(IntPtr items,IShellItem dest);
 void DeleteItem(IShellItem item,IProgressSink sink); void DeleteItems(IntPtr items);
 void NewItem(IShellItem dest,uint attrs,[MarshalAs(UnmanagedType.LPWStr)]string name,[MarshalAs(UnmanagedType.LPWStr)]string template,IProgressSink sink);
 void PerformOperations(); void GetAnyOperationsAborted([MarshalAs(UnmanagedType.Bool)]out bool aborted);
}
[ComVisible(true), Guid("04B0F1A7-9490-44BC-96E1-4296A31252E2"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
public interface IProgressSink {
 [PreserveSig]int StartOperations(); [PreserveSig]int FinishOperations(int result);
 [PreserveSig]int PreRenameItem(uint f,IShellItem i,[MarshalAs(UnmanagedType.LPWStr)]string n);
 [PreserveSig]int PostRenameItem(uint f,IShellItem i,[MarshalAs(UnmanagedType.LPWStr)]string n,int h,IShellItem o);
 [PreserveSig]int PreMoveItem(uint f,IShellItem i,IShellItem d,[MarshalAs(UnmanagedType.LPWStr)]string n);
 [PreserveSig]int PostMoveItem(uint f,IShellItem i,IShellItem d,[MarshalAs(UnmanagedType.LPWStr)]string n,int h,IShellItem o);
 [PreserveSig]int PreCopyItem(uint f,IShellItem i,IShellItem d,[MarshalAs(UnmanagedType.LPWStr)]string n);
 [PreserveSig]int PostCopyItem(uint f,IShellItem i,IShellItem d,[MarshalAs(UnmanagedType.LPWStr)]string n,int h,IShellItem o);
 [PreserveSig]int PreDeleteItem(uint f,IShellItem i);
 [PreserveSig]int PostDeleteItem(uint f,IShellItem i,int h,IShellItem o);
 [PreserveSig]int PreNewItem(uint f,IShellItem d,[MarshalAs(UnmanagedType.LPWStr)]string n);
 [PreserveSig]int PostNewItem(uint f,IShellItem d,[MarshalAs(UnmanagedType.LPWStr)]string n,[MarshalAs(UnmanagedType.LPWStr)]string t,uint a,int h,IShellItem o);
 [PreserveSig]int UpdateProgress(uint total,uint done); [PreserveSig]int ResetTimer(); [PreserveSig]int PauseTimer(); [PreserveSig]int ResumeTimer();
}
[ComVisible(true),ClassInterface(ClassInterfaceType.None)]
public class RecycleSink:IProgressSink {
 public int LastResult=0; public bool Refused=false;
 public int StartOperations(){return 0;} public int FinishOperations(int h){LastResult=h;return 0;}
 public int PreDeleteItem(uint f,IShellItem i){if((f&0x80)==0){Refused=true;return unchecked((int)0x80004004);}return 0;}
 public int PostDeleteItem(uint f,IShellItem i,int h,IShellItem o){if(h<0)LastResult=h;return 0;}
 public int PreRenameItem(uint f,IShellItem i,string n){return 0;} public int PostRenameItem(uint f,IShellItem i,string n,int h,IShellItem o){return 0;}
 public int PreMoveItem(uint f,IShellItem i,IShellItem d,string n){return 0;} public int PostMoveItem(uint f,IShellItem i,IShellItem d,string n,int h,IShellItem o){return 0;}
 public int PreCopyItem(uint f,IShellItem i,IShellItem d,string n){return 0;} public int PostCopyItem(uint f,IShellItem i,IShellItem d,string n,int h,IShellItem o){return 0;}
 public int PreNewItem(uint f,IShellItem d,string n){return 0;} public int PostNewItem(uint f,IShellItem d,string n,string t,uint a,int h,IShellItem o){return 0;}
 public int UpdateProgress(uint total,uint done){return 0;}public int ResetTimer(){return 0;}public int PauseTimer(){return 0;}public int ResumeTimer(){return 0;}
}
public static class RecycleOnly {
 [DllImport("shell32.dll",CharSet=CharSet.Unicode,PreserveSig=false)]
 static extern void SHCreateItemFromParsingName(string path,IntPtr context,ref Guid iid,out IShellItem item);
 public static string Send(string path){
  IFileOperation op=null;IShellItem item=null;
  try{
   op=(IFileOperation)Activator.CreateInstance(Type.GetTypeFromCLSID(new Guid("3AD05575-8857-4850-9277-11B85BDB8E09")));
   // 强制回收、永久删除警告、遇错返回；从不提供永久删除的后备路径。
   op.SetOperationFlags(0x00080000|0x00100000|0x4000|0x0400|0x0040|0x0010|0x0004);
   Guid iid=new Guid("43826D1E-E718-42EE-BC55-A1E261C37BFE");
   SHCreateItemFromParsingName(path,IntPtr.Zero,ref iid,out item);
   var sink=new RecycleSink();op.DeleteItem(item,sink);op.PerformOperations();
   bool aborted;op.GetAnyOperationsAborted(out aborted);
   if(sink.Refused)return "拒绝永久删除";
   if(aborted || sink.LastResult<0)return "回收失败 HRESULT="+sink.LastResult.ToString("X8");
   return File.Exists(path)||Directory.Exists(path)?"原路径仍存在":"已回收";
  }catch(Exception e){return "失败: "+e.Message;}
  finally{if(item!=null)Marshal.ReleaseComObject(item);if(op!=null)Marshal.ReleaseComObject(op);}
 }
}

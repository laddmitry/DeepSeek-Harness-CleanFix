# Local-only USER_RIGHTS operations; caller must be an elevated isolated-VM operator.
if (-not ('DshProvisionRights' -as [type])) {
Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.ComponentModel;
using System.Runtime.InteropServices;
public static class DshProvisionRights {
 [StructLayout(LayoutKind.Sequential)] struct US { public ushort Length,MaximumLength; public IntPtr Buffer; }
 [StructLayout(LayoutKind.Sequential)] struct OA { public int Length; public IntPtr RootDirectory,ObjectName; public uint Attributes; public IntPtr SecurityDescriptor,SecurityQualityOfService; }
 [DllImport("C:\\Windows\\System32\\advapi32.dll")] static extern uint LsaOpenPolicy(IntPtr name,ref OA attributes,uint access,out IntPtr handle);
 [DllImport("C:\\Windows\\System32\\advapi32.dll")] static extern uint LsaEnumerateAccountRights(IntPtr handle,byte[] sid,out IntPtr rights,out uint count);
 [DllImport("C:\\Windows\\System32\\advapi32.dll")] static extern uint LsaAddAccountRights(IntPtr handle,byte[] sid,[In] US[] rights,uint count);
 [DllImport("C:\\Windows\\System32\\advapi32.dll")] static extern uint LsaFreeMemory(IntPtr memory);
 [DllImport("C:\\Windows\\System32\\advapi32.dll")] static extern uint LsaClose(IntPtr handle);
 [DllImport("C:\\Windows\\System32\\advapi32.dll")] static extern uint LsaNtStatusToWinError(uint status);
 static void Check(uint status) { if(status!=0)throw new Win32Exception((int)LsaNtStatusToWinError(status)); }
 static IntPtr Open() { var attributes=new OA(); attributes.Length=Marshal.SizeOf<OA>(); IntPtr handle;Check(LsaOpenPolicy(IntPtr.Zero,ref attributes,0x810,out handle));return handle; }
 public static string[] Read(byte[] sid) {
  var handle=Open();IntPtr memory=IntPtr.Zero;
  try { uint count;var status=LsaEnumerateAccountRights(handle,sid,out memory,out count);if(status==0xc0000034)return new string[0];Check(status);
   var rows=new List<string>();for(int i=0;i<count;i++){var item=Marshal.PtrToStructure<US>(IntPtr.Add(memory,i*Marshal.SizeOf<US>()));rows.Add(Marshal.PtrToStringUni(item.Buffer,item.Length/2));}return rows.ToArray();
  }finally{if(memory!=IntPtr.Zero)LsaFreeMemory(memory);LsaClose(handle);}
 }
 public static void Grant(byte[] sid) {
  string[] names={"SeAssignPrimaryTokenPrivilege","SeIncreaseQuotaPrivilege"};var rows=new US[names.Length];var handle=Open();
  try{for(int i=0;i<names.Length;i++){rows[i].Length=(ushort)(names[i].Length*2);rows[i].MaximumLength=(ushort)(rows[i].Length+2);rows[i].Buffer=Marshal.StringToHGlobalUni(names[i]);}Check(LsaAddAccountRights(handle,sid,rows,(uint)rows.Length));}
  finally{foreach(var row in rows)if(row.Buffer!=IntPtr.Zero)Marshal.FreeHGlobal(row.Buffer);LsaClose(handle);}
 }
}
'@
}

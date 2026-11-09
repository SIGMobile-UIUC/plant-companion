param([string]$RepositoryRoot = (Join-Path $PSScriptRoot '../..'))
$ErrorActionPreference='Stop'
$root=[IO.Path]::GetFullPath($RepositoryRoot)
$source=Join-Path $root 'artwork/AppLogo.png'
if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -ne '6a37d349ed249b8545c0c3e583405094eb6efe609abbc5f23629ad675c7a15bd') { throw 'Approved original AppLogo.png differs' }
Add-Type -AssemblyName System.Drawing
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @'
using System;
using System.Drawing;
using System.Drawing.Imaging;
public static class LauncherRaster {
  static bool Mask(int x,int y,int n,string mask) {
    double px=x+.5,py=y+.5,c=n*.5;
    if(mask=="circle")return (px-c)*(px-c)+(py-c)*(py-c)<=c*c;
    return true;
  }
  public static void Write(string input,string output,int n,double fraction,bool opaque,string mask) {
    using(var src=new Bitmap(input))using(var dst=new Bitmap(n,n,opaque?PixelFormat.Format24bppRgb:PixelFormat.Format32bppArgb)) {
      double w=n*fraction,h=w*src.Height/src.Width,left=(n-w)/2,top=(n-h)/2;
      for(int y=0;y<n;y++)for(int x=0;x<n;x++){
        var c=opaque||mask!="square"?Color.FromArgb(255,22,63,46):Color.Transparent;
        bool inside=x+.5>=left&&x+.5<left+w&&y+.5>=top&&y+.5<top+h;
        if(inside){
          int sx=Math.Min(src.Width-1,(int)Math.Floor((x+.5-left)*src.Width/w)),sy=Math.Min(src.Height-1,(int)Math.Floor((y+.5-top)*src.Height/h));
          var p=src.GetPixel(sx,sy);
          if(p.A>0&&!Mask(x,y,n,mask))throw new Exception("Mask would crop approved artwork");
          if(opaque||mask!="square"){double a=p.A/255.0;c=Color.FromArgb(255,(int)Math.Round(p.R*a+22*(1-a)),(int)Math.Round(p.G*a+63*(1-a)),(int)Math.Round(p.B*a+46*(1-a)));}
          else c=p;
        }
        if(!Mask(x,y,n,mask))c=Color.Transparent;
        dst.SetPixel(x,y,c);
      }
      dst.Save(output,ImageFormat.Png);
    }
  }
}
'@
$outputs=@()
function Write-Icon([string]$Relative,[int]$Size,[double]$Fraction=0.87890625,[bool]$Opaque=$true,[string]$Mask='square') {
 $target=Join-Path $root $Relative
 [IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($target)) | Out-Null
 [LauncherRaster]::Write($source,$target,$Size,$Fraction,$Opaque,$Mask)
 $script:outputs+=[ordered]@{path=$Relative.Replace('\','/');size=$Size;logoWidthFraction=$Fraction;opaque=$Opaque;mask=$Mask;sha256=(Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash.ToLowerInvariant();bytes=(Get-Item -LiteralPath $target).Length}
}
foreach($density in @(@('mdpi',48,108),@('hdpi',72,162),@('xhdpi',96,216),@('xxhdpi',144,324),@('xxxhdpi',192,432))) {
 $base='app/android/app/src/main/res/mipmap-'+$density[0]+'/'
 Write-Icon ($base+'ic_launcher.png') $density[1]
 # A true circular bitmap for pre-adaptive roundIcon fallback.
 Write-Icon ($base+'ic_launcher_round.png') $density[1] 0.80 $false 'circle'
 # 55/108 artwork width leaves the entire mark inside the 66dp safe zone.
 Write-Icon ($base+'ic_launcher_foreground.png') $density[2] (55.0/108) $false
}
$ios=Get-Content -LiteralPath (Join-Path $root 'app/ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json') -Raw | ConvertFrom-Json
foreach($image in $ios.images){
 $size=[double]$image.size.Split('x')[0]*[double]$image.scale.Replace('x','')
 $relative='app/ios/Runner/Assets.xcassets/AppIcon.appiconset/'+$image.filename
 if (-not ($outputs.path -contains $relative)) {Write-Icon $relative ([int]$size)}
}
foreach($size in @(192,512)) {
 Write-Icon ('app/web/icons/Icon-'+$size+'.png') $size
 Write-Icon ('app/web/icons/Icon-maskable-'+$size+'.png') $size 0.65
}
Write-Icon 'app/web/favicon.png' 48
Write-Icon 'app/web/icons/apple-touch-icon.png' 180
[ordered]@{source='artwork/AppLogo.png';sourceSha256='6a37d349ed249b8545c0c3e583405094eb6efe609abbc5f23629ad675c7a15bd';background='#163F2E';method='Nearest-neighbor sampling of the unchanged original with geometric placement; alpha composited only for opaque platform targets. No lettering or pixels redrawn.';optionalMonochrome='Omitted: a faithful standalone monochrome design was not supplied.';outputs=$outputs} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $root 'artwork/platform_icons.json') -Encoding utf8
Write-Output ("Generated and hashed "+$outputs.Count+" platform PNGs from the approved original.")

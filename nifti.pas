unit nifti;
{$IFDEF FPC}{$mode objfpc}{$H+}{$ENDIF}
{$DEFINE CUSTOMCOLORS}
interface
{$IFDEF FPC}
 {$DEFINE GZIP}
{$ENDIF}
{$DEFINE OPENFOREIGN}
//{$DEFINE CPUGRADIENTS} //Computing volume gradients on the GPU is much faster than using the CPU
{$DEFINE CACHEUINT8} //save 8-bit data: faster requires RAM
uses
  {$IFDEF OPENFOREIGN} nifti_foreign, {$ENDIF}
  {$IFDEF CUSTOMCOLORS} colorTable,  {$ENDIF}

  {$IFDEF GZIP}zstream, GZIPUtils,umat,{$ENDIF} //Freepascal includes the handy zstream function for decompressing GZip files
  dialogs, clipbrd, SimdUtils, sysutils,Classes, nifti_types, Math, VectorMath, otsuml;
//Written by Chris Rorden, released under BSD license
//This is the header NIfTI format http://nifti.nimh.nih.gov/nifti-1/
//NIfTI is popular in neuroimaging - should be compatible for Analyze format
//   http://eeg.sourceforge.net/ANALYZE75.pdf
//NIfTI format images have two components:
// 1.) Header data provides image dimensions and details
// 2.) Image data
//These two components can be separate files: MRI.hdr, MRI.img
//  or a single file with the header at the start MRI.nii
//Note raw image daya begins vox_offset bytes into the image data file
//  For example, in a typical NII file, the header is the first 348 bytes,
//  but the image data begins at byte 352 (as this is evenly divisible by 8)
Type
  TNIfTI = Class(TObject)  // This is an actual class definition :
      // Internal class field definitions - only accessible in this unit
      private
        fMat, fInvMat, fMatInOrient: TMat4;
        fMin, fMax, fAutoBalMin, fAutoBalMax, fWindowMin, fWindowMax: single;
        fOpacityPct: integer;
        fScale, fCutoutLow, fCutoutHigh : TVec3;
        fDim, fPermInOrient: TVec3i;
        fHdr, fHdrNoRotation : TNIFTIhdr;
        fKnownOrientation, fIsNativeEndian: boolean;
        fFileName,fShortName, fBidsName: string;
        fVolRGBA: TRGBAs;
        fLabels: TStringList;
        fhistogram: TLUT;
        fIsOverlay, fIsDrawing: boolean; //booleans do not generate 32-bit RGBA images
        {$IFDEF CACHEUINT8}
        fVolumeDisplayed, fVolumesLoaded, fOpacityPctCache8: integer;
        fWindowMinCache8, fWindowMaxCache8: single;
        fCache8: TUInt8s;
        {$ENDIF}
        {$IFDEF CUSTOMCOLORS}
        clut: TCLUT;
        {$ELSE}
        fLUT: TLUT;
        {$ENDIF}
        //init functions compute volume min/max and set default min/max brightness/contrast
        procedure InitUInt8();
        procedure InitInt16();
        procedure InitFloat32();
        //display functions apply windo min/max to generate image with desired brightness/contrast
        procedure SetDisplayMinMaxRGB24();
        procedure DisplayLabel2Uint8();
        //procedure SetDisplayMinMaxFloat32();
        //procedure SetDisplayMinMaxInt16();
        //procedure SetDisplayMinMaxUint8();
        procedure SetDisplayMinMax(isForceRefresh: boolean = false); overload;
        procedure Convert2Float();
        procedure VolumeReslice(tarMat: TMat4; tarDim: TVec3i; isLinearReslice: boolean);
        procedure VolumeReorient();
        //procedure ApplyVolumeReorient(perm: TVec3i; outR: TMat4);
        function OpenNIfTI(): boolean;
        procedure MakeBorg(voxelsPerDimension: integer);
        procedure initHistogram();

        procedure ApplyCutout();
        function LoadRaw(FileName : AnsiString; out isNativeEndian: boolean): boolean;
        {$IFDEF GZIP}function LoadGz(FileName : AnsiString; out isNativeEndian: boolean): boolean;{$ENDIF}
        function skipVox(): int64; //if fVolumeDisplayed > 0, skip this many VOXELS for first byte of data
        //function skipBytes(): int64; //if fVolumeDisplayed > 0, skip this many BYTES for first byte of data
        //function skipRawVolBytes(): TUInt8s;
        function VoiDescriptivesLabels(VoiRawBytes: TUInt8s): TStringList;
        //procedure robustMinMax(var rMin, rMax: single);
      public
        fRawVolBytes: TUInt8s;
        LoadFewVolumes: boolean;
        HiddenByCutout: boolean;
        MaxVox: integer; //maximum number of voxels in any dimension
        property IsNativeEndian: boolean read fIsNativeEndian;
        property VolumeDisplayed: integer read fVolumeDisplayed; //indexed from 0 (0..VolumesLoaded-1)
        property VolumesLoaded: integer read fVolumesLoaded; //1 for 3D data, for 4D 1..hdr.dim[4] depending on RAM
        property KnownOrientation: boolean read fKnownOrientation;
        {$IFDEF CUSTOMCOLORS}
        property ColorTable: TLUT read clut.fLUT write clut.fLUT;
        function FullColorTable: TCLUTrec;
        property CX: TCLUT read clut write clut;
        {$ELSE}
        property ColorTable: TLUT read fLUT write fLUT;
        {$ENDIF}
        //procedure SmoothMaskedImages();
        property Drawing: boolean read fIsDrawing;
        function NeedsUpdate(): boolean;
        procedure SaveAsSourceOrient(NiftiOutName: string; rawVolBytes: TUInt8s);
        function FracToSlice(Frac: TVec3): TVec3i; //given volume fraction return zero-indexed slice
        function FracShiftSlice(Frac: TVec3; sliceMove: TVec3i): TVec3; //move a desired number of slices
        function FracMM(Frac: TVec3): TVec3; //return mm coordinates given volume fraction
        function MMFrac(MM: TVec3): TVec3; //return frac coordinates given volume mm
        function VoiDescriptives(VoiRawBytes: TUInt8s): TStringList;
        function VoxIntensityString(vox: integer): string; overload;
        function VoxIntensityString(vox: TVec3i): string; overload;
        function VoxIntensity(vox: integer): single; overload; //return intensity of voxel at coordinate
        function VoxIntensity(vox: TVec3i): single; overload; //return intensity of voxel at coordinate
        property OpacityPercent: integer read fOpacityPct write fOpacityPct; //0=transparent, 50=translucent, 100=opaque
        property Histogram: TLUT read fhistogram;
        property VolumeMin: single read fMin; //darkest voxel in volume
        property VolumeMax: single read fMax; //brightest voxel in volume
        property SuggestedDisplayMin: single read fAutoBalMin;
        property SuggestedDisplayMax: single read fAutoBalMax;
        property DisplayMin: single read fWindowMin; //write warning: changes only isplayed if you call SetDisplayMinMax()
        property DisplayMax: single read fWindowMax; //write warning: changes only isplayed if you call SetDisplayMinMax()
        property Header: TNIFTIhdr read fhdr;
        property HeaderNoRotation: TNIfTIhdr read fHdrNoRotation;
        property Scale: TVec3 read fScale;
        property ShortName: String read fShortName;
        property Mat: TMat4 read fMat;
        property InvMat: TMat4 read fInvMat;
        property Dim: TVec3i read fDim;
        property VolRGBA: TRGBAs read fVolRGBA;
        property VolRawBytes: TUInt8s read fRawVolBytes;
        property Filename: String read fFileName;
        property BidsName: String read fBidsName;
        procedure Sharpen();
        procedure Smooth();
        procedure RemoveHaze();
        procedure GPULoadDone();
        function Load(niftiFileName: string): boolean; overload;
        function Load(niftiFileName: string; tarMat: TMat4; tarDim: TVec3i; isInterpolate: boolean; volumeNumber: integer = 0; isKeepContrast: boolean = false): boolean; overload;
        procedure SetDisplayMinMax(newMin, newMax: single); overload;
        procedure SetDisplayMinMaxNoUpdate(newMin, newMax: single); overload;
        procedure SetCutoutNoUpdate(CutoutLow, CutoutHigh: TVec3);
        function DisplayMinMax2Uint8(isForceRefresh: boolean = false): TUInt8s;
        procedure SetDisplayColorScheme(clutFileName: string; cTag: integer);
        procedure SetDisplayVolume(newDisplayVolume: integer);
        procedure ForceUpdate;
        {$IFDEF CPUGRADIENTS}
        procedure CreateGradientVolume (rData: TRGBAs; Xsz,Ysz,Zsz: integer; out Vol : TRGBAs);
        function GenerateGradientVolume: TRGBAs; overload;
        {$ENDIF}
        constructor Create(); overload; //empty volume
        constructor Create(niftiFileName: string; backColor: TRGBA; lLoadFewVolumes: boolean; lMaxVox: integer; out isOK: boolean); overload; //background
        constructor Create(niftiFileName: string; backColor: TRGBA; tarMat: TMat4; tarDim: TVec3i; isInterpolate: boolean; out isOK: boolean; lLoadFewVolumes: boolean = true; lMaxVox: integer = 640); overload; //overlay
        constructor Create(tarMat: TMat4; tarDim: TVec3i); overload; //blank drawing
        function IsLabels: boolean; //e.g. template map: should be drawn nearest neighbor (border of area 19 and 17 is NOT 18)
        destructor Destroy; override;
  end;
  {$IFDEF CPUGRADIENTS}
  procedure CreateGradientVolumeX (rData: TUInt8s; Xsz,Ysz,Zsz, isRGBA: integer; out VolRGBA : TRGBAs);
  {$ENDIF}

implementation

uses reorient;

procedure  Coord(var lV: TVec4; lMat: TMat4);
//transform X Y Z by matrix
var
  lXi,lYi,lZi: single;
begin
  lXi := lV[0]; lYi := lV[1]; lZi := lV[2];
  lV[0] := (lXi*lMat[0,0]+lYi*lMat[0,1]+lZi*lMat[0,2]+lMat[0,3]);
  lV[1] := (lXi*lMat[1,0]+lYi*lMat[1,1]+lZi*lMat[1,2]+lMat[1,3]);
  lV[2] := (lXi*lMat[2,0]+lYi*lMat[2,1]+lZi*lMat[2,2]+lMat[2,3]);
end;

function voxelCenter(frac: single; dim: integer): single;
//if 3 voxels span 0..1 then centers are at 0.25/0.5/0.75 - voxels frac is 1/(n+1)
//if 4 voxels, centers 0.125, 0.375. 0.625. 0.875
// so val 0..0.33 will return 0.25
var
  sliceFrac: double;
  slice: integer;
begin
  if (dim < 2) then exit(0.5);
  sliceFrac := 1/dim;
  slice := trunc(frac/sliceFrac);
  if (slice >= dim) then slice := dim - 1; //e.g. frac 1.0 = top slice
  if (slice < 0) then slice := 0; //only with negative fraction!
  result := (sliceFrac * (slice+0.5));
end;

function frac2slice(frac: single; dim: integer): integer;
var
  sliceFrac: double;
begin
     if (dim < 2) then exit(0);
     sliceFrac := 1/dim;
     result := trunc(frac/sliceFrac);
     if (result >= dim) then result := dim - 1; //e.g. frac 1.0 = top slice
     if (result < 0) then result := 0; //only with negative fraction!
end;

function SliceMM(vox0: TVec3; Mat: TMat4): TVec3;
var
  v4: TVec4;
begin
  v4 := Vec4(vox0.x, vox0.y, vox0.z, 1.0); //Vec4(X-1,Y-1,Z-1, 1); //indexed from 0, use -1 if indexed from 1
  Coord(v4, Mat);
  result := Vec3(v4.x, v4.y, v4.z);
end;


function TNIfTI.skipVox(): int64;
begin
     if (fVolumeDisplayed <= 0) or (fIsOverlay) then exit(0);
     result := prod(fDim) * fVolumeDisplayed;
end;

procedure  TNIfTI.ForceUpdate;
begin
  fWindowMinCache8 := infinity;
end;

function TNIfTI.IsLabels: boolean;
//return TRUE for neurolabels
begin
 result :=  (fHdr.intent_code= kNIFTI_INTENT_LABEL);
end;

function TNIfTI.VoiDescriptivesLabels(VoiRawBytes: TUInt8s): TStringList;
const
  kTab = chr(9);
var
   i, j, nVox, nVoi, sumTotal : integer;
   sumVois, sumVoisNot0: TUInt32s;
begin
     result := TStringList.Create();
     if fLabels.Count < 1 then exit;
     nVox := length(VoiRawBytes);
     nVoi := fLabels.Count;
     if (nVox <> (dim.x * dim.y * dim.z)) then exit;
     setlength(sumVois, nVoi);
     setlength(sumVoisNot0, nVoi);
     for i := 0 to (nVoi -1) do begin
         sumVois[i] := 0;
         sumVoisNot0[i] := 0;
     end;
     sumTotal := 0;
     for i := 0 to (nVox -1) do begin
         j :=  round(VoxIntensity(i));
         if j = 0 then continue;
         sumVois[j] := sumVois[j] + 1;
         if (VoiRawBytes[i] = 0) then continue;
         sumTotal := sumTotal + 1;
         if (j >= nVox) then continue;
         sumVoisNot0[j] := sumVoisNot0[j] + 1;
     end;
     result.Add('Background image: '+ShortName);
     result.Add(format('TotalVoxelsNotZero%s%d', [kTab, sumTotal]));
     result.Add('Index'+kTab+'Name'+kTab+'numVox'+kTab+'numVoxNotZero');
     for i := 0 to (fLabels.Count -1) do begin
         if fLabels[i] = '' then continue;
         if sumVoisNot0[i] < 1 then continue;
         result.Add(format('%d%s"%s"%s%d%s%d', [i,kTab, fLabels[i], kTab, sumVois[i], kTab, sumVoisNot0[i]]));
     end;
     sumVois := nil;
     sumVoisNot0 := nil;
end;

function RealToStr(lR: double {was extended}; lDec: integer): string;
begin
     result := FloatToStrF(lR, ffFixed,7,lDec);
end;

function TNIfTI.VoiDescriptives(VoiRawBytes: TUInt8s): TStringList;
const
  kTab = ' ';//chr(9);
var
   x, y, z, lInc, i, nVox, nVoi : integer;
   lROIVol: array [1..3] of integer;
   lROISum,lROISumSqr,lROImin,lROImax:array [1..3] of double;
   lCC,lVal,lSD,lROImean: double;
   lLabelStr, lStr: string;
   mm: TVec3;
procedure  AddVal( lRA: integer);
begin
  inc(lROIVol[lRA]);
  lROISum[lRA] := lROISum[lRA]+lVal;
  lROISumSqr[lRA] := lROISumSqr[lRA] + sqr(lVal);
  if lVal > lROImax[lRA] then
    lROImax[lRA] := lVal;
  if lVal < lROImin[lRA] then
    lROImin[lRA] := lVal;
end;//nested AddVal()
begin
     if fLabels.Count > 0 then begin
       result := VoiDescriptivesLabels(VoiRawBytes);
       exit;
     end;
     lLabelStr := 'Drawing ';
     result := TStringList.Create();
     result.Add('Background image: '+ShortName);
     nVox := length(VoiRawBytes);
     if (nVox <> (dim.x * dim.y * dim.z)) then exit;
     //center of mass
     for i := 1 to 3 do
         lROISum[i] := 0;
     i := 0;
     nVoi := 0;
     for z := 0 to (dim.z-1) do
         for y := 0 to (dim.y-1) do
             for x := 0 to (dim.x-1) do begin
                 if (VoiRawBytes[i] > 0) then begin
                    nVoi := nVoi + 1;
                    lROISum[1] := lROISum[1] + x;
                    lROISum[2] := lROISum[2] + y;
                    lROISum[3] := lROISum[3] + z;
                 end;
                 i := i + 1;
             end;
     if (nVoi = 0) then begin
        result.Add('Drawing empty');
        exit;
     end;
     lROISum[1] := lROISum[1] / nVoi;
     lROISum[2] := lROISum[2] / nVoi;
     lROISum[3] := lROISum[3] / nVoi;
     //mm := FracMM(Vec3(lROISum[1],lROISum[2],lROISum[3]));
     result.Add('Drawing Center of mass XYZvox '+RealToStr(lROISum[1],2)+'x'+RealToStr(lROISum[2],2)+'x'+RealToStr(lROISum[3],2));
     mm := SliceMM(Vec3(lROISum[1],lROISum[2],lROISum[3]), Mat);
     result.Add('Drawing Center of mass XYZmm '+RealToStr(mm.x,2)+'x'+RealToStr(mm.y,2)+'x'+RealToStr(mm.z,2));
     //statistics
     for i := 1 to 3 do begin
         lROIVol[i] := 0;
         lROISum[i] := 0;
         lROISumSqr[i] := 0;
         lROImax[i] := NegInfinity;
         lROImin[i] := Infinity;
     end;
     for i := 0 to (nVox -1) do begin
         if (VoiRawBytes[i] = 0) then continue;
         lVal := VoxIntensity(i);
         AddVal(1);
	 if lVal <> 0 then
	    AddVal(2);
	 if lVal > 0 then
	    AddVal(3);
     end;
     result.Add('Background image: '+ShortName);
     for lInc := 1 to 3 do begin
     	if lROIVol[lInc] > 1 then begin
     	   lSD := (lROISumSqr[lInc] - ((Sqr(lROISum[lInc]))/lROIVol[lInc]));
     	   if  (lSD > 0) then
     	       lSD :=  Sqrt ( lSD/(lROIVol[lInc]-1))
     	   else
     	       lSD := 0;
     	end else
     	    lSD := 0;
     	//next compute mean
     	if lROIVol[lInc] > 0 then begin
     	   lROImean := lROISum[lInc]/lROIVol[lInc];
     	end else begin //2/2008
                  lROImin[lInc] := 0;
                  lROImax[lInc] := 0;
                  lROImean := 0;
        end;
     	lcc := ((lROIVol[lInc]/1000)*fHdr.pixdim[1]*fHdr.pixdim[2]*fHdr.pixdim[3]);
     	case lInc of
     		3: lStr := 'VOI  >0 ';
     		2: lStr := 'VOI <>0 ';
     		else lStr := 'VOI     ';
     	end;
     	lStr := lStr+' nvox(cc)=min/mean/max=SD: '+inttostr(round(lROIVol[lInc]))+kTab+RealToStr(lCC,2)+kTab+'='+kTab+RealToStr(lROIMin[lInc],4)+kTab+realToStr(lROIMean,4)+kTab+realToStr(lROIMax[lInc],4)+kTab+'='+kTab+realtostr(lSD,4);
     	result.Add(lLabelStr+ lStr);
     end;
end;

function TNIfTI.VoxIntensityString(vox: integer): string; overload;//return intensity or label of voxel at coordinate
var
   f : single;
   i: integer;
begin
     f :=  VoxIntensity(vox);
     if IsLabels then begin
         i := round(f);
         if (i >= 0) and (i < fLabels.Count) then
            result := fLabels[i]
         else
             result := '';
     end else
         result := format('%3.6g', [f]);
end;

function TNIfTI.VoxIntensityString(vox: TVec3i): string; overload;//return intensity of voxel at coordinate
var
  i: integer;
begin
     i := vox.x + (vox.y * dim.x) + (vox.z * (dim.x * dim.y));
     result := '';
     if (i < 0) or (i >= (dim.x * dim.y * dim.z)) then exit;
     result := VoxIntensityString(i);
end;

function TNIfTI.VoxIntensity(vox: integer): single; overload; //return intensity of voxel at coordinate
var
  vol32 : TFloat32s;
  vol16: TInt16s;
  vol8: TUInt8s;
begin
     result := 0;
     if (vox < 0) or (vox >= (dim.x * dim.y * dim.z)) then exit;
     vox := vox + skipVox;
     vol8 := fRawVolBytes;
     vol16 := TInt16s(vol8);
     vol32 := TFloat32s(vol8);
     if fHdr.datatype = kDT_UINT8 then
       result := vol8[vox]
     else if fHdr.datatype = kDT_INT16 then
          result := vol16[vox]
     else if fHdr.datatype = kDT_FLOAT then
          result := vol32[vox];
     result := (result * fHdr.scl_slope) + fHdr.scl_inter;
end;

function TNIfTI.VoxIntensity(vox: TVec3i): single; overload;//return intensity of voxel at coordinate
var
  i: integer;
begin
     result := 0;
     i := vox.x + (vox.y * dim.x) + (vox.z * (dim.x * dim.y));
     if (i < 0) or (i >= (dim.x * dim.y * dim.z)) then exit;
     result := VoxIntensity(i);
end;

function TNIfTI.FracToSlice(Frac: TVec3): TVec3i;
begin
     result.X := frac2slice(Frac.X, fDim.X);
     result.Y := frac2slice(Frac.Y, fDim.Y);
     result.Z := frac2slice(Frac.Z, fDim.Z);
end;

function TNIfTI.FracShiftSlice(Frac: TVec3; sliceMove: TVec3i): TVec3; //move a desired number of slices
//align to slices
begin
     //if 3 voxels span 0..1 then centers are at 0.25/0.5/0.75 - voxels frac is 1/(n+1)
  result.X := Frac.X + (sliceMove.X * (1.0/(fDim.X+1)));
  result.Y := Frac.Y + (sliceMove.Y * (1.0/(fDim.Y+1)));
  result.Z := Frac.Z + (sliceMove.Z * (1.0/(fDim.Z+1)));
  result.X := voxelCenter(result.X, fDim.X);
  result.Y := voxelCenter(result.Y, fDim.Y);
  result.Z := voxelCenter(result.Z, fDim.Z);
end;

function TNIfTI.MMFrac(MM: TVec3): TVec3;
var
   lV: TVec4;
begin
     lV := Vec4(MM.X,MM.Y,MM.Z,1);
     if (fDim.X < 1) or (fDim.Y < 1) or (fDim.Z < 1) then
          exit(vec3(0.5, 0.5, 0.5));
     Coord (lV,InvMat);
     result.X := (lV[0]+1)/fDim.X;
     result.Y := (lV[1]+1)/fDim.Y;
     result.Z := (lV[2]+1)/fDim.Z;
end;

function TNIfTI.FracMM(Frac: TVec3): TVec3;
var
  vox0: TVec3;
begin
     //result := sliceFrac2D; exit;
     vox0.x := trunc(Frac.x * Dim.x);
     vox0.y := trunc(Frac.y * Dim.y);
     vox0.z := trunc(Frac.z * Dim.z);
     vox0.x := min(vox0.x, Dim.x -1); //0..Dim-1, perfect unless sliceFrac2D.x=1
     vox0.y := min(vox0.y, Dim.y -1); //0..Dim-1, perfect unless sliceFrac2D.y=1
     vox0.z := min(vox0.z, Dim.z -1); //0..Dim-1, perfect unless sliceFrac2D.z=1
     //result := vox0; exit;
     result := SliceMM(vox0, Mat);
end;

{$IFDEF CUSTOMCOLORS}
function TNIfTI.FullColorTable: TCLUTrec;
begin
 result := clut.FullColorTable;
end;
{$ENDIF}

procedure printf (lS: AnsiString);
begin
{$IFNDEF WINDOWS} writeln(lS); {$ENDIF}
end;

{$IFDEF CPUGRADIENTS}
const
 kRGBAclear : TRGBA = (r: 0; g: 0; b: 0; a:0);

Function XYZI (X1,X2,Y1,Y2,Z1,Z2: single; Center: byte): TRGBA;
//gradients in range -1..1
//input voxel intensity to the left,right,anterior,posterior,inferior,superior and center
// Output RGBA image where values correspond to X,Y,Z gradients and ImageIntensity
//AlphaT will make a voxel invisible if center intensity is less than specified value
// Voxels where there is no gradient (no edge boundary) are made transparent
var
  X,Y,Z,Dx: single;
begin
  Result := kRGBAclear;
  if Center < 1 then
    exit; //intensity less than threshold: make invisible
  X := X1-X2;
  Y := Y1-Y2;
  Z := Z1-Z2;
  Dx := sqrt(X*X+Y*Y+Z*Z);
  if Dx = 0 then
    exit;  //no gradient - set intensity to zero.
  result.r :=round((X/(Dx*2)+0.5)*255); //X
  result.g :=round((Y/(Dx*2)+0.5)*255); //Y
  result.b := round((Z/(Dx*2)+0.5)*255); //Z
  result.a := Center;
end;

function Sobel (rawData: TUInt8s; Xsz,Ysz, I : integer; var GradMag: single): TRGBA;
//this computes intensity gradients using 3D Sobel filter.
//Much slower than central difference but more accurate
//http://www.aravind.ca/cs788h_Final_Project/gradient_estimators.htm
var
  Y,Z,J: integer;
  Xp,Xm,Yp,Ym,Zp,Zm: single;
begin
  GradMag := 0;//gradient magnitude
  Result := kRGBAclear;
  if rawData[i] < 1 then
    exit; //intensity less than threshold: make invisible
  Y := XSz; //each row is X voxels
  Z := YSz*XSz; //each plane is X*Y voxels
  //X:: cols: +Z +0 -Z, rows -Y +0 +Y
  J := I+1;
  Xp := rawData[J-Y+Z]+3*rawData[J-Y]+rawData[J-Y-Z]
        +3*rawData[J+Z]+6*rawData[J]+3*rawData[J-Z]
        +rawData[J+Y+Z]+3*rawData[J+Y]+rawData[J+Y-Z];
  J := I-1;
  Xm := rawData[J-Y+Z]+3*rawData[J-Y]+rawData[J-Y-Z]
        +3*rawData[J+Z]+6*rawData[J]+3*rawData[J-Z]
        +rawData[J+Y+Z]+3*rawData[J+Y]+rawData[J+Y-Z];
  //Y:: cols: +Z +0 -Z, rows -X +0 +X
  J := I+Y;
  Yp := rawData[J-1+Z]+3*rawData[J-1]+rawData[J-1-Z]
        +3*rawData[J+Z]+6*rawData[J]+3*rawData[J-Z]
        +rawData[J+1+Z]+3*rawData[J+1]+rawData[J+1-Z];
  J := I-Y;
  Ym := rawData[J-1+Z]+3*rawData[J-1]+rawData[J-1-Z]
        +3*rawData[J+Z]+6*rawData[J]+3*rawData[J-Z]
        +rawData[J+1+Z]+3*rawData[J+1]+rawData[J+1-Z];
  //Z:: cols: +Z +0 -Z, rows -X +0 +X
  J := I+Z;
  Zp := rawData[J-Y+1]+3*rawData[J-Y]+rawData[J-Y-1]
        +3*rawData[J+1]+6*rawData[J]+3*rawData[J-1]
        +rawData[J+Y+1]+3*rawData[J+Y]+rawData[J+Y-1];
  J := I-Z;
  Zm := rawData[J-Y+1]+3*rawData[J-Y]+rawData[J-Y-1]
        +3*rawData[J+1]+6*rawData[J]+3*rawData[J-1]
        +rawData[J+Y+1]+3*rawData[J+Y]+rawData[J+Y-1];
  result := XYZI (Xm,Xp,Ym,Yp,Zm,Zp,rawData[I]);
  GradMag :=  sqrt( sqr(Xm-Xp)+sqr(Ym-Yp)+sqr(Zm-Zp));//gradient magnitude
end;

procedure NormVol (var Vol: TFloat32s);
var
  n,i: integer;
  mx,mn: single;
begin
  n := length(Vol);
  if n < 1 then
    exit;
  mx := Vol[0];
  mn := Vol[0];
  for i := 0 to (n-1) do begin
    if Vol[i] > mx then
      mx := Vol[i];
    if Vol[i] < mn then
      mn := Vol[i];
  end;
  if mx = mn then
    exit;
  mx := mx-mn;//range
  for i := 0 to (n-1) do
    Vol[i] := (Vol[i]-mn)/mx;
end;

function SmoothVol (var rawData: TUInt8s; lXdim,lYdim,lZdim: integer): integer;
//simple 3D smoothing for noisy data - makes images blurry
//this is useful prior to generating gradients, as it reduces stepping
const
  kCen : single = 2/3; //center of kernel is 2/3
  kEdge : single = 1/6; //voxel on each edge is 1/6
var
   lSmoothImg,lSmoothImg2: TFloat32s;
   lSliceSz,lZPos,lYPos,lX,lY,lZ,lnVox,lVox: integer;
begin
   result := -1;
   lSliceSz := lXdim*lYdim;
   lnVox := lSliceSz*lZDim;
    if (lnVox < 0) or (lXDim < 3) or (lYDim < 3) or (lZDim < 3) then begin
	    printf('Smooth3DNII error: Image dimensions are not large enough to filter.');
	    exit;
   end;
  setlength(lSmoothImg,lnVox);
  setlength(lSmoothImg2,lnVox);
  for lX := 0 to (lnVox-1) do
    lSmoothImg[lX] := rawData[lX];
  for lX := 0 to (lnVox-1) do
    lSmoothImg2[lX] := rawData[lX];
  //X-direction - copy from SmoothImg -> SmoothImg2
  for lZ := 2 to lZdim-1 do begin
    lZPos := (lZ-1)*lSliceSz;
    for lY := 2 to lYdim-1 do begin
      lYPos := (lY-1)*lXdim;
      for lX := 2 to lXdim-1 do begin
            lVox := lZPos+lYPos+lX-1;//-1 as indexed from 0
            lSmoothImg2[lVox] := (lSmoothImg[lVox-1]*kEdge)+(lSmoothImg[lVox]*kCen)+(lSmoothImg[lVox+1]*kEdge);
      end; {lX}
    end; {lY}
  end; {lZ loop for X-plane}
  //Y-direction - copy from SmoothImg2 -> SmoothImg
  for lZ := 2 to lZdim-1 do begin
    lZPos := (lZ-1)*lSliceSz;
    for lY := 2 to lYdim-1 do begin
      lYPos := (lY-1)*lXdim;
      for lX := 2 to lXdim-1 do begin
            lVox := lZPos+lYPos+lX-1;//-1 as indexed from 0
            lSmoothImg[lVox] := (lSmoothImg2[lVox-lXdim]*kEdge)+(lSmoothImg2[lVox]*kCen)+(lSmoothImg2[lVox+lXdim]*kEdge);
      end; {lX}
    end; {lY}
  end; {lZ loop for Y-plane}
  //Z-direction - copy from SmoothImg -> SmoothImg2
  for lZ := 2 to lZdim-1 do begin
    lZPos := (lZ-1)*lSliceSz;
    for lY := 2 to lYdim-1 do begin
      lYPos := (lY-1)*lXdim;
      for lX := 2 to lXdim-1 do begin
            lVox := lZPos+lYPos+lX-1;//-1 as indexed from 0
            lSmoothImg2[lVox] := (lSmoothImg[lVox-lSliceSz]*kEdge)+(lSmoothImg[lVox]*kCen)+(lSmoothImg[lVox+lSliceSz]*kEdge);
      end; //x
    end; //y
  end; //z
   //next make this in the range 0..255
  for lX := 0 to (lnVox-1) do
    rawData[lX] := round(lSmoothImg2[lX]);
  lSmoothImg2 := nil;
  lSmoothImg := nil;
end;

procedure CreateGradientVolumeX (rData: TUInt8s; Xsz,Ysz,Zsz, isRGBA: integer; out VolRGBA : TRGBAs);
//compute gradients for each voxel... Output texture in form RGBA
//  RGB will represent as normalized X,Y,Z gradient vector:  Alpha will store gradient magnitude
const
  kEdgeSharpness = 255;//value 1..255: 1=all edges transparent, 255=edges very opaque
var
  X, Y,Z,Index,XYsz : Integer;
  VolData: TUInt8s;
  tRGBA: TRGBAs;
  GradMagS: TFloat32s;
Begin
  tRGBA := nil;
  if (XSz < 1) or (YSz < 1) or (ZSz < 1) then
    exit;
  XYsz :=  Xsz*Ysz;
  Setlength (VolData,XYsz*Zsz);
  if isRGBA = 1 then begin
     tRGBA := TRGBAs(rData );
     for Index := 0 to ((XYsz*Zsz)-1) do
      VolData[Index] := tRGBA[Index].a;
  end else
    for Index := 0 to ((XYsz*Zsz)-1) do
      VolData[Index] := rData[Index];
  //next line: blur the data
  SmoothVol (VolData, Xsz,Ysz,Zsz);
  SetLength (VolRGBA, XYsz*Zsz);
  SetLength (GradMagS,XYsz*Zsz);
  for Index := 0 to ((XYsz*Zsz)-1) do //we can not compute gradients for image edges, so initialize volume so all voxels are transparent
    VolRGBA[Index] := kRGBAclear;
  for Z := 1 To Zsz - 2 do  //for X,Y,Z dimensions indexed from zero, so := 1 gives 1 voxel border
    for Y := 1 To Ysz - 2 do
      for X := 1 To Xsz - 2 do begin
        Index := (Z * XYsz) + (Y * Xsz) + X;
        //Next line computes gradients using Sobel filter
        VolRGBA[Index] := Sobel (VolData, Xsz,Ysz, Index,GradMagS[Index]);
      end;//X
  VolData := nil;
  //next: generate normalized gradient magnitude values
  NormVol (GradMagS);
  for Index := 0 to ((XYsz*Zsz)-1) do
    VolRGBA[Index].A := round(GradMagS[Index]*kEdgeSharpness);
  GradMagS := nil;
end;

procedure TNIfTI.CreateGradientVolume (rData: TRGBAs; Xsz,Ysz,Zsz: integer; out Vol : TRGBAs);
begin
     CreateGradientVolumeX (TUInt8s(rData), Xsz,Ysz,Zsz, 1, Vol);
end;

function TNIfTI.GenerateGradientVolume: TRGBAs;
var
  GradRGBA : TRGBAs;
begin
 //CreateGradientVolume (fVolRGBA, fDim.X, fDim.Y, fDim.Z, GradRGBA);
 CreateGradientVolumeX (TUInt8s(fVolRGBA), fDim.X, fDim.Y, fDim.Z, 1, GradRGBA);
 result := GradRGBA;
end;
{$ENDIF} //CPU gradients

function reorient(dim : TVec3i; R: TMat4; out residualR: TMat4; out perm : TVec3i): boolean;
//compute dimension permutations and flips to reorient volume to standard space
//From Xiangrui Li's BSD 2-Clause Licensed code
// https://github.com/xiangruili/dicm2nii/blob/master/nii_viewer.m
var
  a, rotM: TMat4;
  i,j: integer;
  flp,ixyz : TVec3i;
begin
  result := false;
  a := TMat4.Identity;
  //memo1.lines.add(writeMat('R',R));
  for i := 0 to 3 do
      for j := 0 to 3 do
          a[i,j] := abs(R[i,j]);
  //memo1.lines.add(writeMat('a',a));
  //first column = x
  ixyz.x := 1;
  if (a[1,0] > a[0,0]) then ixyz.x := 2;
  if (a[2,0] > a[0,0]) and (a[2,0]> a[1,0]) then ixyz.x := 3;
  //second column = y: constrained as must not be same row as x
  if (ixyz.x = 1) then begin
     if (a[1,1] > a[2,1]) then
        ixyz.y := 2
     else
         ixyz.y := 3;
  end else if (ixyz.x = 2) then begin
     if (a[0,1] > a[2,1]) then
        ixyz.y := 1
     else
         ixyz.y := 3;
  end else begin //ixyz.x = 3
     if (a[0,1] > a[1,1]) then
        ixyz.y := 1
     else
         ixyz.y := 2;
  end;
  //third column = z:constrained as x+y+z = 1+2+3 = 6
  ixyz.z := 6 - ixyz.y - ixyz.x;
  perm.v[ixyz.x-1] := 1;
  perm.v[ixyz.y-1] := 2;
  perm.v[ixyz.z-1] := 3;
  //sort columns  R(:,1:3) = R(:,perm);
  rotM := R;
  for i := 0 to 3 do
      for j := 0 to 2 do
          R[i,j] := rotM[i,perm.v[j]-1];
  //compute if dimension is flipped
  if R[0,0] < 0 then flp.x := 1 else flp.x := 0;
  if R[1,1] < 0 then flp.y := 1 else flp.y := 0;
  if R[2,2] < 0 then flp.z := 1 else flp.z := 0;
  if (perm.x = 1) and (perm.y = 2) and (perm.z = 3) and (flp.x = 0) and (flp.y = 0) and (flp.z = 0) then exit;//already oriented correctly
  result := true; //reorient required!
  rotM := TMat4.Identity;
  rotM[0,0] := 1-flp.x*2;
  rotM[1,1] := 1-flp.y*2;
  rotM[2,2] := 1-flp.z*2;
  rotM[0,3] := ((dim.v[perm.x-1])-1) * flp.x;
  rotM[1,3] := ((dim.v[perm.y-1])-1) * flp.y;
  rotM[2,3] := ((dim.v[perm.z-1])-1) * flp.z;
  residualR := rotM.Inverse;
  residualR *= R;
  for i := 0 to 2 do
      if (flp.v[i] <> 0) then perm.v[i] := -perm.v[i];
end;

function SForm2Mat(hdr: TNIFTIhdr): TMat4;
begin
  result := TMat4.Identity;
  result[0,0] := hdr.srow_x[0]; result[0,1] := hdr.srow_x[1]; result[0,2] := hdr.srow_x[2]; result[0,3] := hdr.srow_x[3];
  result[1,0] := hdr.srow_y[0]; result[1,1] := hdr.srow_y[1]; result[1,2] := hdr.srow_y[2]; result[1,3] := hdr.srow_y[3];
  result[2,0] := hdr.srow_z[0]; result[2,1] := hdr.srow_z[1]; result[2,2] := hdr.srow_z[2]; result[2,3] := hdr.srow_z[3];
end;

procedure Mat2SForm(m: TMat4; var hdr: TNIFTIhdr);
begin
 hdr.srow_x[0] := m[0,0]; hdr.srow_x[1] := m[0,1]; hdr.srow_x[2] := m[0,2]; hdr.srow_x[3] := m[0,3];
 hdr.srow_y[0] := m[1,0]; hdr.srow_y[1] := m[1,1]; hdr.srow_y[2] := m[1,2]; hdr.srow_y[3] := m[1,3];
 hdr.srow_z[0] := m[2,0]; hdr.srow_z[1] := m[2,1]; hdr.srow_z[2] := m[2,2]; hdr.srow_z[3] := m[2,3];
end;

procedure ApplyVolumeReorient(perm: TVec3i; outR: TMat4; var fDim: TVec3i; var fScale : TVec3; var fHdr  : TNIFTIhdr; var rawVolBytes: TUInt8s);
var
   flp: TVec3i;
    inScale: TVec3;
    inDim, inStride, outStride : TVec3i;
    in8: TUInt8s;
    in16, out16: TInt16s;
    in32, out32: TInt32s;
    in24, out24: TRGBs;
    xOffset, yOffset, zOffset: array of integer;
    voxOffset, byteOffset, volBytes,vol, volumesLoaded,  x,y,z, i: integer;
begin
  if (perm.x = 1) and (perm.y = 2) and (perm.z = 3) then begin
     Mat2SForm(outR, fHdr); //could skip: no change!
    exit;
  end;
  for i := 0 to 2 do begin
       flp.v[i] := 0;
       if (perm.v[i] < 0) then flp.v[i] := 1;
       perm.v[i] := abs(perm.v[i]);
   end;
  if (perm.x = perm.y) or (perm.x = perm.z) or (perm.y = perm.z) or ((perm.x+perm.y+perm.z) <> 6 ) then begin
     Mat2SForm(outR, fHdr); //could skip: bogus
    exit;
  end;
  inDim := fDim;
 inStride.x := 1;
 inStride.y := inDim.x;
 inStride.z := inDim.x * inDim.y;
 outStride.x := inStride.v[perm.x-1];
 outStride.y := inStride.v[perm.y-1];
 outStride.z := inStride.v[perm.z-1];
 //set outputs
 fDim.x := inDim.v[perm.x-1];
 fDim.y := inDim.v[perm.y-1];
 fDim.z := inDim.v[perm.z-1];
 inscale := fScale;
 fScale.x := inScale.v[perm.x-1];
 fScale.y := inScale.v[perm.y-1];
 fScale.z := inScale.v[perm.z-1];
 Mat2SForm(outR, fHdr);
 //setup lookup tables
 setlength(xOffset, fDim.x);
 if flp.x = 1 then begin
    for x := 0 to (fDim.x - 1) do
        xOffset[fDim.x-1-x] := x*outStride.x;
 end else
     for x := 0 to (fDim.x - 1) do
         xOffset[x] := x*outStride.x;
 setlength(yOffset, fDim.y);
 if flp.y = 1 then begin
    for y := 0 to (fDim.y - 1) do
        yOffset[fDim.y-1-y] := y*outStride.y;
 end else
     for y := 0 to (fDim.y - 1) do
         yOffset[y] := y*outStride.y;
 setlength(zOffset, fDim.z);
 if flp.z = 1 then begin
    for z := 0 to (fDim.z - 1) do
        zOffset[fDim.z-1-z] := z*outStride.z;
 end else
     for z := 0 to (fDim.z - 1) do
         zOffset[z] := z*outStride.z;
 //copy data
 volBytes := fHdr.Dim[1]*fHdr.Dim[2]*fHdr.Dim[3]* (fHdr.bitpix shr 3);
 volumesLoaded := length(rawVolBytes) div volBytes;
 SetLength(in8, volBytes);
 if volumesLoaded < 1 then exit;
 for vol := 1 to volumesLoaded do begin
   byteOffset := (vol-1) * volBytes;
   voxOffset := fHdr.Dim[1]*fHdr.Dim[2]*fHdr.Dim[3]* (vol-1);
   in8 := Copy(rawVolBytes, byteOffset, volBytes);
   if fHdr.bitpix = 8 then begin
      i := voxOffset;
      for z := 0 to (fDim.z - 1) do
          for y := 0 to (fDim.y - 1) do
              for x := 0 to (fDim.x - 1) do begin
                rawVolBytes[i] := in8[xOffset[x]+yOffset[y]+zOffset[z]];
                i := i + 1;
              end;
   end;
   if fHdr.bitpix = 16 then begin
      in16 := TInt16s(in8);
      out16 := TInt16s(rawVolBytes);
      i := voxOffset;
      for z := 0 to (fDim.z - 1) do
          for y := 0 to (fDim.y - 1) do
              for x := 0 to (fDim.x - 1) do begin
                out16[i] := in16[xOffset[x]+yOffset[y]+zOffset[z]];
                i := i + 1;
              end;
   end;
   if fHdr.bitpix = 24 then begin
      in24 := TRGBs(in8);
      out24 := TRGBs(rawVolBytes);
      i := voxOffset;
      for z := 0 to (fDim.z - 1) do
          for y := 0 to (fDim.y - 1) do
              for x := 0 to (fDim.x - 1) do begin
                out24[i] := in24[xOffset[x]+yOffset[y]+zOffset[z]];
                i := i + 1;
              end;
   end;
   if fHdr.bitpix = 32 then begin
      in32 := TInt32s(in8);
      out32 := TInt32s(rawVolBytes);
      i := voxOffset;
      for z := 0 to (fDim.z - 1) do
          for y := 0 to (fDim.y - 1) do
              for x := 0 to (fDim.x - 1) do begin
                out32[i] := in32[xOffset[x]+yOffset[y]+zOffset[z]];
                i := i + 1;
              end;
   end;
 end; //for vol 1..volumesLoaded
 xOffset := nil;
 yOffset := nil;
 zOffset := nil;
 in8 := nil;
 fHdr.dim[1] := fDim.X;
 fHdr.dim[2] := fDim.Y;
 fHdr.dim[3] := fDim.Z;
end;

function ChangeFileExtX(fnm, ext: string): string; //treat ".nii.gz" as single extension
begin
 result := changefileext(fnm,'');
 if upcase(extractfileext(result)) = '.NII' then
      result := changefileext(result,'');
 result := result + ext;
end;

procedure TNIfTI.SaveAsSourceOrient(NiftiOutName: string; rawVolBytes: TUInt8s);
//for drawing rotate back to orientation of input image!
var
   oHdr  : TNIFTIhdr;
   oDim, oPerm: TVec3i;
   oScale: TVec3;
   oPad32: Uint32; //nifti header is 348 bytes padded with 4
   nBytes,nVox: int64;
   i: integer;
   mStream : TMemoryStream;
   zStream: TGZFileStream;
   lExt: string;
begin
 nBytes := length(rawVolBytes);
 nVox := prod(fDim);
 oHdr := fHdr;
 if (nBytes = nVox) then
   oHdr.bitpix := 8
 else if (nBytes = (2*nVox)) then
   oHdr.bitpix := 16
 else if (nBytes = (4*nVox)) then
   oHdr.bitpix := 32
 else
     exit;
 if oHdr.bitpix = 8 then
   oHdr.datatype := kDT_UNSIGNED_CHAR
 else if oHdr.bitpix = 16 then
   oHdr.datatype := kDT_INT16
 else
     oHdr.datatype := kDT_FLOAT;
 oDim := fDim;
 oScale := fScale;
 //output perm reverses input permute
 //fPermInOrient
 oPerm := pti(1,2,3);
 for i := 0 to 2 do
     if abs(fPermInOrient.v[i]) = 1 then
       oPerm.X := (i+1) * sign(fPermInOrient.v[i]);
 for i := 0 to 2 do
     if abs(fPermInOrient.v[i]) = 2 then
       oPerm.Y := (i+1) * sign(fPermInOrient.v[i]);
 for i := 0 to 2 do
     if abs(fPermInOrient.v[i]) = 3 then
       oPerm.Z := (i+1) * sign(fPermInOrient.v[i]);
 //showmessage(format('%d %d %d -> %d %d %d', [fPermInOrient.X, fPermInOrient.Y, fPermInOrient.Z, oPerm.X, oPerm.y, oPerm.Z]));
 ApplyVolumeReorient(oPerm, fMatInOrient, oDim, oScale, oHdr, rawVolBytes);
 mStream := TMemoryStream.Create;
 oHdr.vox_offset :=  sizeof(oHdr) + 4;
 mStream.Write(oHdr,sizeof(oHdr));
 oPad32 := 4;
 mStream.Write(oPad32, 4);
 mStream.Write(rawVolBytes[0],length(rawVolBytes));
  mStream.Position := 0;
 FileMode := fmOpenWrite;   //FileMode := fmOpenRead;
 lExt := uppercase(extractfileext(NiftiOutName));
 if (lExt = '.GZ') or (lExt = '.VOI') then begin  //save gz compressed
    if (lExt = '.GZ') then
       NiftiOutName := ChangeFileExtX(NiftiOutName,'.nii.gz'); //img.gz -> img.nii.gz
    zStream := TGZFileStream.Create(NiftiOutName, gzopenwrite);
    zStream.CopyFrom(mStream, mStream.Size);
    zStream.Free;
 end else begin
     if (lExt <> '.NII') then
        NiftiOutName := NiftiOutName + '.nii';
     mStream.SaveToFile(NiftiOutName); //save uncompressed
 end;
 mStream.Free;
 FileMode := fmOpenRead;

end;

procedure TNIfTI.VolumeReorient();
//rotate volume so X ~ left->right, Y ~ posterior->anterior, Z ~ inferior->superior
//rotations are lossless so only to nearest orthogonal
var
   outR: TMat4;
begin
     if fHdr.sform_code = kNIFTI_XFORM_UNKNOWN then exit;
     //R := SForm2Mat(fHdr);
     if not reorient(fDim, fMatInOrient, outR, fPermInOrient)  then exit;
     //ApplyVolumeReorient(fPerm, outR);
     //fPermInOrient.Z := abs(fPermInOrient.Z);
     //showmessage(format('%d %d %d ', [fPermInOrient.X, fPermInOrient.Y, fPermInOrient.Z]));

     ApplyVolumeReorient(fPermInOrient, outR, fDim, fScale, fHdr, fRawVolBytes);
     fMat := outR;
end;

procedure TNIfTI.MakeBorg(voxelsPerDimension: integer);
const
 Border : integer= 4;//margin so we can calculate gradients at edge
var
  d, I, X, Y, Z: integer;
 F: array of single;
 mn, mx, slope: single;
begin
 d := voxelsPerDimension;
 fBidsName := '';
 NII_Clear(fhdr);
 fhdr.dim[1] := d;
 fhdr.dim[2] := d;
 fhdr.dim[3] := d;
 fhdr.bitpix := 8;
 fhdr.datatype := kDT_UNSIGNED_CHAR;
 fhdr.intent_code:= kNIFTI_INTENT_NONE;
 fKnownOrientation := true;
 if (voxelsPerDimension <= Border) then begin
    SetLength(fRawVolBytes, d*d*d);
    for I := 0 to d*d*d-1 do
        fRawVolBytes[I] := 0;
    exit;
 end;
 SetLength(F, d * d * d);
 slope := 0.005;
 I := 0;
 for X := 0 to d-1 do
  for Y := 0 to d-1 do
   for Z := 0 to d-1 do
   begin
    if (X < Border) or (Y < Border) or (Z < Border) or ((d-X) < Border) or ((d-Y) < Border) or ((d-Z) < Border) then
     F[I] := 0
    else
     F[I] := sin(slope *x *y) + sin(slope *y * z) + sin(slope *z * x);
    Inc(I);
   end;
 //next find range...
 mn := F[0];
 for I := 0 to d*d*d-1 do
  if F[I] < mn then
   mn := F[I];
 mx := F[0];
 for I := 0 to d*d*d-1 do
  if F[I] > mx then
   mx := F[I];
 slope := 255/(mx-mn);
 SetLength(fRawVolBytes, d*d*d);
 for I := 0 to d*d*d-1 do begin
  if F[I] <= 0 then
   fRawVolBytes[I] := 0
  else
   fRawVolBytes[I] := Round((F[I]-mn)*slope);
 end;
 F := nil;
end;

procedure SwapImg(var  rawData: TUInt8s; bitpix: integer);
var
   i16s: TInt16s;
   i32s: TInt32s;
   f64s: TFloat64s;
   i, n: integer;
begin
     if bitpix < 15 then exit;
     if bitpix = 16 then begin
        n := length(rawData) div 2;
        i16s := TInt16s(rawData);
        for i := 0 to (n-1) do
            i16s[i] := swap2(i16s[i]);
     end;
     if bitpix = 32 then begin
        n := length(rawData) div 4;
        i32s := TInt32s(rawData);
        for i := 0 to (n-1) do
            swap4(i32s[i]);
     end;
     if bitpix = 64 then begin
        n := length(rawData) div 8;
        f64s := TFloat64s(rawData);
        for i := 0 to (n-1) do
            Xswap8r(f64s[i]);
     end;
end;

procedure nifti_quatern_to_mat44( out lR :TMat4;
                             var qb, qc, qd,
                             qx, qy, qz,
                             dx, dy, dz, qfac : single);
var
   a,b,c,d,xd,yd,zd: double;
begin
   //a := qb;
   b := qb;
   c := qc;
   d := qd;
   //* last row is always [ 0 0 0 1 ] */
   lR := TMat4.Identity;
   //* compute a parameter from b,c,d */
   a := 1.0 - (b*b + c*c + d*d) ;
   if( a < 1.e-7 ) then begin//* special case */
     a := 1.0 / sqrt(b*b+c*c+d*d) ;
     b := b*a ; c := c*a ; d := d*a ;//* normalize (b,c,d) vector */
     a := 0.0 ;//* a = 0 ==> 180 degree rotation */
   end else begin
     a := sqrt(a) ; //* angle = 2*arccos(a) */
   end;
   //* load rotation matrix, including scaling factors for voxel sizes */
   if dx > 0 then
      xd := dx
   else
       xd := 1;
   if dy > 0 then
      yd := dy
   else
       yd := 1;
   if dz > 0 then
      zd := dz
   else
       zd := 1;
   if( qfac < 0.0 ) then zd := -zd ;//* left handedness? */
   lR[0,0] := (a*a+b*b-c*c-d*d) * xd ;
   lR[0,1] := 2.0 * (b*c-a*d        ) * yd ;
   lR[0,2]:= 2.0 * (b*d+a*c        ) * zd ;
   lR[1,0] := 2.0 * (b*c+a*d        ) * xd ;
   lR[1,1] := (a*a+c*c-b*b-d*d) * yd ;
   lR[1,2] :=  2.0 * (c*d-a*b        ) * zd ;
   lR[2,0] := 2.0 * (b*d-a*c        ) * xd ;
   lR[2,1] :=  2.0 * (c*d+a*b        ) * yd ;
   lR[2,2] :=         (a*a+d*d-c*c-b*b) * zd ;
   //* load offsets */
   lR[0,3]:= qx ;
   lR[1,3]:= qy ;
   lR[2,3]:= qz ;
end;

function Quat2Mat( var lHdr: TNIfTIHdr ): boolean;
var lR :TMat4;
begin
  result := false;
  if (lHdr.sform_code <> kNIFTI_XFORM_UNKNOWN) or (lHdr.qform_code <= kNIFTI_XFORM_UNKNOWN) or (lHdr.qform_code > kNIFTI_XFORM_MNI_152) then
     exit;
  result := true;
  nifti_quatern_to_mat44(lR,lHdr.quatern_b,lHdr.quatern_c,lHdr.quatern_d,
  lHdr.qoffset_x,lHdr.qoffset_y,lHdr.qoffset_z,
  lHdr.pixdim[1],lHdr.pixdim[2],lHdr.pixdim[3],
  lHdr.pixdim[0]);
  lHdr.srow_x[0] := lR[0,0];
  lHdr.srow_x[1] := lR[0,1];
  lHdr.srow_x[2] := lR[0,2];
  lHdr.srow_x[3] := lR[0,3];
  lHdr.srow_y[0] := lR[1,0];
  lHdr.srow_y[1] := lR[1,1];
  lHdr.srow_y[2] := lR[1,2];
  lHdr.srow_y[3] := lR[1,3];
  lHdr.srow_z[0] := lR[2,0];
  lHdr.srow_z[1] := lR[2,1];
  lHdr.srow_z[2] := lR[2,2];
  lHdr.srow_z[3] := lR[2,3];
  lHdr.sform_code := kNIFTI_XFORM_SCANNER_ANAT;
end;

procedure NoMat( var lHdr: TNIfTIHdr );
//situation where no matrix is provided
//var
//   lR :TMat4;
begin
     if (lHdr.sform_code > kNIFTI_XFORM_UNKNOWN) or (lHdr.qform_code > kNIFTI_XFORM_UNKNOWN) then exit;
     if (lHdr.srow_x[0] <> 0) or (lHdr.srow_x[1] <> 0) or (lHdr.srow_x[2] <> 0) then exit;
     if lHdr.pixdim[1] = 0 then lHdr.pixdim[1] := 1;
     if lHdr.pixdim[2] = 0 then lHdr.pixdim[2] := 1;
     if lHdr.pixdim[3] = 0 then lHdr.pixdim[3] := 1;
     lHdr.srow_x[0] := lHdr.pixdim[1];
     lHdr.srow_x[1] := 0;
     lHdr.srow_x[2] := 0;
     lHdr.srow_x[3] := 0;
     lHdr.srow_y[0] := 0;
     lHdr.srow_y[1] := lHdr.pixdim[2];
     lHdr.srow_y[2] := 0;
     lHdr.srow_y[3] := 0;
     lHdr.srow_z[0] := 0;
     lHdr.srow_z[1] := 0;
     lHdr.srow_z[2] := lHdr.pixdim[3];
     lHdr.srow_z[3] := 0;
end;

function Nifti2to1(h2 : TNIFTI2hdr): TNIFTIhdr;
type
  tmagic = packed record
    case byte of
      0:(b1,b2,b3,b4 : ansichar); //word is 16 bit
      1:(l: longint);
  end;
var
  h1 : TNIFTIhdr;
  i: integer;
  magic: tmagic;
begin
  NII_Clear(h1);
  magic.b1 := h2.magic[1];
  magic.b2 := h2.magic[2];
  magic.b3 := h2.magic[3];
  magic.b4 := h2.magic[4];
  h1.magic := magic.l;
  h1.dim_info := h2.dim_info; //MRI slice order
  for i := 0 to 7 do
   h1.dim[i] := h2.dim[i];
  h1.intent_p1 := h2.intent_p1;
  h1.intent_p2 := h2.intent_p2;
  h1.intent_p3 := h2.intent_p3;
  h1.intent_code := h2.intent_code;
  if (h2.intent_code >= 3000) and (h2.intent_code <= 3012) then begin //https://www.nitrc.org/forum/attachment.php?attachid=342&group_id=454&forum_id=1955
     showmessage('NIfTI2 image has CIfTI intent code ('+inttostr(h2.intent_code)+'): open as an overlay with Surfice');
  end;
  h1.datatype := h2.datatype;
  h1.bitpix := h2.bitpix;
  h1.slice_start := h2.slice_start;
  for i := 0 to 7 do
   h1.pixdim[i] := h2.pixdim[i];
  h1.vox_offset := h2.vox_offset;
  h1.scl_slope := h2.scl_slope;
  h1.slice_end := h2.slice_end;
  h1.slice_code := h2.slice_code; //e.g. ascending
  h1.cal_min:= h2.cal_min;
  h1.cal_max:= h2.cal_max;
  h1.xyzt_units := h2.xyzt_units; //e.g. mm and sec
  h1.slice_duration := h2.slice_duration; //time for one slice
  h1.toffset := h2.toffset; //time axis to shift
  for i := 1 to 80 do
   h1.descrip[i] := h2.descrip[i];
  for i := 1 to 24 do
   h1.aux_file[i] := h2.aux_file[i];
  h1.qform_code := h2.qform_code;
  h1.sform_code := h2.sform_code;
  h1.quatern_b := h2.quatern_b;
  h1.quatern_c := h2.quatern_c;
  h1.quatern_d := h2.quatern_d;
  h1.qoffset_x := h2.qoffset_x;
  h1.qoffset_y := h2.qoffset_y;
  h1.qoffset_z := h2.qoffset_z;
  for i := 0 to 3 do begin
     h1.srow_x[i] := h2.srow_x[i];
     h1.srow_y[i] := h2.srow_y[i];
     h1.srow_z[i] := h2.srow_z[i];
  end;
  for i := 1 to 16 do
     h1.intent_name[i] := h2.intent_name[i];
  h1.HdrSz := 348;
  result := h1;
end;

function Nifti2to1(Stream:TFileStream): TNIFTIhdr; overload;
var
  h2 : TNIFTI2hdr;
  h1 : TNIFTIhdr;
  lSwappedReportedSz: LongInt;
begin
  h1.HdrSz:= 0; //error
  Stream.Seek(0,soFromBeginning);
  Stream.ReadBuffer (h2, SizeOf (TNIFTI2hdr));
  lSwappedReportedSz := h2.HdrSz;
  swap4(lSwappedReportedSz);
  if (lSwappedReportedSz = SizeOf (TNIFTI2hdr)) then begin
    printf('Not yet able to handle byte-swapped NIfTI2');
    //NIFTIhdr_SwapBytes(h2);
    //isNativeEndian := false;
    exit(h1);
  end;
  if (h2.HdrSz <> SizeOf (TNIFTI2hdr)) then exit(h1);
  result := Nifti2to1(h2);
end;

{$IFDEF GZIP}
function Nifti2to1(Stream:TGZFileStream): TNIFTIhdr; overload;
var
  h2 : TNIFTI2hdr;
  h1 : TNIFTIhdr;
  lSwappedReportedSz: LongInt;
begin
  h1.HdrSz:= 0; //error
  Stream.Seek(0,soFromBeginning);
  Stream.ReadBuffer (h2, SizeOf (TNIFTI2hdr));
  lSwappedReportedSz := h2.HdrSz;
  swap4(lSwappedReportedSz);
  if (lSwappedReportedSz = SizeOf (TNIFTI2hdr)) then begin
    printf('Not yet able to handle byte-swapped NIfTI2');
    exit(h1);
  end;
  if (h2.HdrSz <> SizeOf (TNIFTI2hdr)) then exit(h1);
  result := Nifti2to1(h2);
end;

function TNIfTI.LoadGZ(FileName : AnsiString; out isNativeEndian: boolean): boolean;
//FSL compressed nii.gz file
var
  Stream: TGZFileStream;
  volBytes: int64;
  lSwappedReportedSz : LongInt;
begin
 isNativeEndian := true;
 result := false;
 Stream := TGZFileStream.Create (FileName, gzopenread);
 Try
  {$warn 5058 off}Stream.ReadBuffer (fHdr, SizeOf (TNIFTIHdr));{$warn 5058 on}
  lSwappedReportedSz := fHdr.HdrSz;
  swap4(lSwappedReportedSz);
  if (lSwappedReportedSz = SizeOf (TNIFTIHdr)) then begin
    NIFTIhdr_SwapBytes(fHdr);
     isNativeEndian := false;
  end;
  if fHdr.HdrSz <> SizeOf (TNIFTIHdr) then begin
    fHdr := Nifti2to1(Stream);
    if fHdr.HdrSz <> SizeOf (TNIFTIHdr) then begin
       printf('Unable to read image '+Filename);
       //Stream.Free; //Finally ALWAYS executed!
       exit;
    end;
  end;
  if (fHdr.bitpix <> 8) and (fHdr.bitpix <> 16) and (fHdr.bitpix <> 24) and (fHdr.bitpix <> 32) and (fHdr.bitpix <> 64) then begin
   printf('Unable to load '+Filename+' - this software can only read 8,16,24,32,64-bit NIfTI files.');
   exit;
  end;
  Quat2Mat(fHdr);
  //read the image data
  volBytes := fHdr.Dim[1]*fHdr.Dim[2]*fHdr.Dim[3]* (fHdr.bitpix div 8);
  if  (fVolumeDisplayed > 0) and (fVolumeDisplayed < fHdr.dim[4]) and (fIsOverlay) then begin
      Stream.Seek(round(fHdr.vox_offset)+(fVolumeDisplayed*volBytes),soFromBeginning);
  end else begin
      fVolumeDisplayed := 0;
      Stream.Seek(round(fHdr.vox_offset),soFromBeginning);
  end;
  if (fHdr.dim[4] > 1) and (not fIsOverlay) then begin
     if LoadFewVolumes then
       fVolumesLoaded :=  trunc((16777216.0 * 4) /volBytes)
     else
         fVolumesLoaded :=  trunc(2147483647.0 /volBytes);
     if fVolumesLoaded < 1 then fVolumesLoaded := 1;
     if fVolumesLoaded > fHdr.dim[4] then fVolumesLoaded := fHdr.dim[4];
     volBytes := volBytes * fVolumesLoaded;
     //vol := SimpleGetInt(extractfilename(Filename)+' select volume',1,1,fHdr.dim[4]);
     //Stream.Seek((vol-1)*volBytes,soFromCurrent);
  end;
  SetLength (fRawVolBytes, volBytes);
  Stream.ReadBuffer (fRawVolBytes[0], volBytes);
  if not isNativeEndian then
   SwapImg(fRawVolBytes, fHdr.bitpix);
 Finally
  Stream.Free;
 End; { Try }
 result := true;
end;
{$ENDIF}

function TNIfTI.LoadRaw(FileName : AnsiString; out isNativeEndian: boolean): boolean;// Load 3D data                                 }
//Uncompressed .nii or .hdr/.img pair
var
   lSwappedReportedSz: LongInt;
   volBytes: int64;
   Stream : TFileStream;

begin
 isNativeEndian := true;
 result := false;
 Stream := TFileStream.Create (FileName, fmOpenRead or fmShareDenyWrite);
 Try
  Stream.ReadBuffer (fHdr, SizeOf (TNIFTIHdr));
  lSwappedReportedSz := fHdr.HdrSz;
  swap4(lSwappedReportedSz);
  if (lSwappedReportedSz = SizeOf (TNIFTIHdr)) then begin
     NIFTIhdr_SwapBytes(fHdr);
     isNativeEndian := false;
  end;
  if fHdr.HdrSz <> SizeOf (TNIFTIHdr) then begin
    fHdr := Nifti2to1(Stream);
    if fHdr.HdrSz <> SizeOf (TNIFTIHdr) then begin
       printf('Unable to read image '+Filename);
       //Stream.Free; //Finally ALWAYS executed!
       exit;
    end;
  end;
  if (fHdr.bitpix <> 8) and (fHdr.bitpix <> 16) and (fHdr.bitpix <> 24) and (fHdr.bitpix <> 32) and (fHdr.bitpix <> 64) then begin
   printf('Unable to load '+Filename+' - this software can only read 8,16,24,32,64-bit NIfTI files.');
   exit;
  end;
  Quat2Mat(fHdr);
  //read the image data
  if extractfileext(Filename) = '.hdr' then begin
   Stream.Free;
   Stream := TFileStream.Create (changefileext(FileName,'.img'), fmOpenRead or fmShareDenyWrite);
  end;
  volBytes := fHdr.Dim[1]*fHdr.Dim[2]*fHdr.Dim[3]* (fHdr.bitpix div 8);
  if  (fVolumeDisplayed > 0) and (fVolumeDisplayed < fHdr.dim[4]) and (fIsOverlay) then begin
      Stream.Seek(round(fHdr.vox_offset)+(fVolumeDisplayed*volBytes),soFromBeginning);
  end else begin
      fVolumeDisplayed := 0;
      Stream.Seek(round(fHdr.vox_offset),soFromBeginning);
  end;
  if (fHdr.dim[4] > 1) and (not fIsOverlay) then begin
     if LoadFewVolumes then
       fVolumesLoaded :=  trunc((16777216.0 * 4) /volBytes)
     else
         fVolumesLoaded :=  trunc(2147483647.0 /volBytes);
     if fVolumesLoaded < 1 then fVolumesLoaded := 1;
     if fVolumesLoaded > fHdr.dim[4] then fVolumesLoaded := fHdr.dim[4];
     volBytes := volBytes * fVolumesLoaded;
     //vol := SimpleGetInt(extractfilename(Filename)+' select volume',1,1,fHdr.dim[4]);
     //Stream.Seek((vol-1)*volBytes,soFromCurrent);
  end;
  SetLength (fRawVolBytes, volBytes);
  Stream.ReadBuffer (fRawVolBytes[0], volBytes);
  if not isNativeEndian then
   SwapImg(fRawVolBytes, fHdr.bitpix);
 Finally
  Stream.Free;
 End;
 result := true;
end;

FUNCTION specialsingle (var s:single): boolean;
//returns true if s is Infinity, NAN or Indeterminate
CONST kSpecialExponent = 255 shl 23;
VAR Overlay: LongInt ABSOLUTE s;
BEGIN
 IF ((Overlay AND kSpecialExponent) = kSpecialExponent) THEN
   RESULT := true
 ELSE
   RESULT := false;
END; //specialsingle()

procedure TNIfTI.GPULoadDone();
begin
     fVolRGBA := nil; //close CPU buffer afterit has been copied to GPU
end;

procedure SmoothFloat(smoothImg: TFloat32s; X,Y,Z: integer);
var
   i, xydim, vx: integer;
   svol32b: TFloat32s;
begin
 if (x < 3) or (y < 3) or (z < 3) then exit;
 xydim := x * y;
 vx := x * y * z;
 setlength(svol32b, vx);
 svol32b := copy(smoothImg,0, vx);
 for i := 1 to (vx-2) do
     smoothImg[i] := svol32b[i-1] + (svol32b[i] * 2) + svol32b[i+1];
 for i := x to (vx-x-1) do  //output *4 input (10bit->12bit)
     svol32b[i] := smoothImg[i-x] + (smoothImg[i] * 2) + smoothImg[i+x];
 for i := xydim to (vx-xydim-1) do  // *4 input (12bit->14bit) : 6 for 8 bit output
     smoothImg[i] := (svol32b[i-xydim] + (svol32b[i] * 2) + svol32b[i+xydim]) * 1/64;
 svol32b := nil;
end;

procedure TNIfTI.Smooth();
//blur image
var
   inSkip, i, vx, xydim: integer;
   vol32, svol32 : TFloat32s;
   vol16: TInt16s;
   vol8: TUInt8s;
begin
 if fHdr.datatype = kDT_RGB then exit;
 if (fHdr.dim[1] < 3) or (fHdr.dim[2] < 3) or (fHdr.dim[3] < 3) then exit;
 if ((fMax-fMin) <= 0) then exit;
 vx := (fHdr.dim[1]*fHdr.dim[2]*fHdr.dim[3]);
 xydim := fHdr.dim[1]*fHdr.dim[2];
 inSkip  := skipVox();
 vol8 := fRawVolBytes;
 vol16 := TInt16s(vol8);
 vol32 := TFloat32s(vol8);
 //smooth
 setlength(svol32,vx);
 if fHdr.datatype = kDT_UINT8 then begin
   for i := 0 to (vx-1) do
       svol32[i] := vol8[inSkip+i];
 end else if fHdr.datatype = kDT_INT16 then begin
     for i := 0 to (vx-1) do
         svol32[i] := vol16[inSkip+i];
 end else if fHdr.datatype = kDT_FLOAT then begin
    svol32 := Copy(vol32, 0, vx);
 end;
 smoothFloat(svol32, fHdr.dim[1], fHdr.dim[2], fHdr.dim[3]);
 if fHdr.datatype = kDT_UINT8 then begin
   for i := inSkip+xydim to (inSkip+vx-1-xydim) do
          vol8[inSkip+i] := round(svol32[i]);
 end else if fHdr.datatype = kDT_INT16 then begin
   for i := inSkip+xydim to (inSkip+vx-1-xydim) do
       vol16[i] := round(svol32[i]);
 end else if fHdr.datatype = kDT_FLOAT then begin
   for i := inSkip+xydim to (inSkip+vx-1-xydim) do
       vol32[i] := svol32[i];
 end;
 svol32 := nil;
 SetDisplayMinMax(true);
end; //smooth()

procedure TNIfTI.Sharpen();
//unsharp mask: emphasize edges by comparing original image to a blurred image
var
   inSkip, i, vx, xydim: integer;
   in32, vol32, svol32 : TFloat32s;
   in16: TInt16s;
   in8: TUInt8s;
   v, mn, mx: single;
begin
 if fHdr.datatype = kDT_RGB then exit;
 if (fHdr.dim[1] < 3) or (fHdr.dim[2] < 3) or (fHdr.dim[3] < 3) then exit;
 if ((fMax-fMin) <= 0) then exit;
 vx := (fHdr.dim[1]*fHdr.dim[2]*fHdr.dim[3]);
 xydim := fHdr.dim[1]*fHdr.dim[2];
 inSkip  := skipVox();
 in8 := fRawVolBytes;
 in16 := TInt16s(fRawVolBytes);
 in32 := TFloat32s(fRawVolBytes);
 //smooth
 setlength(svol32,vx);
 if fHdr.datatype = kDT_UINT8 then begin
   for i := 0 to (vx-1) do
       svol32[i] := in8[inSkip+i];
 end else if fHdr.datatype = kDT_INT16 then begin
     for i := 0 to (vx-1) do
         svol32[i] := in16[inSkip+i];
 end else if fHdr.datatype = kDT_FLOAT then begin
    svol32 := Copy(in32, 0, vx);
 end;
 setlength(vol32,vx);
 vol32 := Copy(svol32, 0, vx);
 smoothFloat(svol32, fHdr.dim[1], fHdr.dim[2], fHdr.dim[3]);
 //find range
 mx := vol32[0];
 mn := mx;
 for i := 0 to (vx-1) do begin
     if vol32[i] > mx then mx := vol32[i];
     if vol32[i] < mn then mn := vol32[i];
 end;
 //unsharp
 for i := 0 to (vx-1) do begin
     v := 2 * vol32[i] - svol32[i];
     if (v >= mn) and (v <= mx) then
        vol32[inSkip+i] := v;
 end;
 if fHdr.datatype = kDT_UINT8 then begin
   for i := inSkip+xydim to (inSkip+vx-1-xydim) do
          in8[inSkip+i] := round(vol32[i]);
 end else if fHdr.datatype = kDT_INT16 then begin
   for i := inSkip+xydim to (inSkip+vx-1-xydim) do
       in16[i] := round(vol32[i]);
 end else if fHdr.datatype = kDT_FLOAT then begin
   for i := inSkip+xydim to (inSkip+vx-1-xydim) do
       in32[i] := vol32[i];
 end;
 svol32 := nil;
 vol32 := nil;
 SetDisplayMinMax(true);
end; //sharpen()

procedure TNIfTI.initHistogram();
var
   i,j,vx, mx: integer;
   v,scale255: single;
   cnt: array [0..255] of integer;
   vol32 : TFloat32s;
   vol16: TInt16s;
   vol8: TUInt8s;
begin
    for i := 0 to 255 do
        fHistogram[i].A := 0;
    vx := (fHdr.dim[1]*fHdr.dim[2]*fHdr.dim[3]);
    if (vx < 1) or ((fMax-fMin) <= 0) then exit;
    vol8 := fRawVolBytes;
    vol16 := TInt16s(vol8);
    vol32 := TFloat32s(vol8);
    for i := 0 to 255 do
        cnt[i] := 0;
    //scale voxels fMin..fMax -> 0..255
    scale255 := 255 / (fMax-fMin);
    j := 1; //for RGBA read Green
    v := 0;
    for i := 0 to (vx - 1) do begin
        if fHdr.datatype = kDT_UINT8 then
           v := vol8[i]
        else if fHdr.datatype = kDT_INT16 then
             v := vol16[i]
        else if fHdr.datatype = kDT_FLOAT then
             v := vol32[i]
        else if fHdr.datatype = kDT_RGB then begin
             v := vol8[j];
             j := j + 3;
        end;
        v := (v * fHdr.scl_slope) + fHdr.scl_inter;
        v := (v - fMin) * scale255;
        if (v < 0) then v := 0;
        if (v > 255) then v := 255;
        inc(cnt[round(v)]);
    end;
    mx := 0;
    for i := 0 to 255 do
        if (cnt[i] > mx) then mx := cnt[i];
    if mx < 2 then exit;
    scale255 := 255/log2(mx);
    for i := 0 to 255 do begin
      if (cnt[i] < 1) then // log2(0) = -inf!
           v := 0
      else
           v := scale255 * log2(cnt[i]);;
        fHistogram[i].A := round(v);
    end;
end;

procedure TNIfTI.initUInt8();
//use header's cal_max and cal_min to rescale 8-bit data
var
  histo: array[0..255] of integer;
  i,vx,mn,mx, thresh, sum: integer;
  vol8: TUInt8s;
begin
  for i := 0 to 255 do
      histo[i] := 0;
  vol8 := fRawVolBytes;
  mn := vol8[0];
  mx := mn;
  vx := (fHdr.dim[1]*fHdr.dim[2]*fHdr.dim[3]);
  for i := 0 to (vx-1) do begin
      if vol8[i] < mn then
         mn := vol8[i];
      if vol8[i] > mx then
         mx := vol8[i];
      inc(histo[vol8[i]]);
  end;
  fMin := (mn * fHdr.scl_slope) + fHdr.scl_inter;
  fMax := (mx * fHdr.scl_slope) + fHdr.scl_inter;
  printf(format('uint8 range %g...%g', [ fMin, fMax]));
  thresh := round(0.01 * vx);
  sum := 0;
  for i := 0 to 255 do begin
      sum := sum + histo[i];
      if (sum > thresh) then break;
  end;
  fAutoBalMin := (i * fHdr.scl_slope) + fHdr.scl_inter;
  sum := 0;
  for i := 255 downto 0 do begin
      sum := sum + histo[i];
      if (sum > thresh) then break;
  end;
  fAutoBalMax := (i * fHdr.scl_slope) + fHdr.scl_inter;
  printf(format('uint8 window %g...%g', [ fAutoBalMin, fAutoBalMax]));
end;

procedure TNIfTI.Convert2Float();
var
  ui16in,ui16temp: TUInt16s;
  i32in,i32temp: TInt32s;
  f64in,f64temp: TFloat64s;
  f32out: TFloat32s;
  i,vx: integer;
begin
  vx := (fHdr.dim[1]*fHdr.dim[2]*fHdr.dim[3]*fVolumesLoaded);
  if (fHdr.datatype = kDT_UINT16) then begin
     ui16in := TUInt16s(fRawVolBytes);
     setlength(ui16temp, vx);
     for i := 0 to (vx-1) do
         ui16temp[i] := ui16in[i];
     fRawVolBytes := nil; //release
     setlength(fRawVolBytes, 4 * vx);
     f32out := TFloat32s(fRawVolBytes);
     for i := 0 to (vx-1) do
         f32out[i] := ui16temp[i];
  end else if (fHdr.datatype = kDT_INT32) then begin
     i32in := TInt32s(fRawVolBytes);
     setlength(i32temp, vx);
     for i := 0 to (vx-1) do
         i32temp[i] := i32in[i];
     fRawVolBytes := nil; //release
     setlength(fRawVolBytes, 4 * vx);
     f32out := TFloat32s(fRawVolBytes);
     for i := 0 to (vx-1) do
         f32out[i] := i32temp[i];
  end else if (fHdr.datatype = kDT_DOUBLE) then begin
   f64in := TFloat64s(fRawVolBytes);
   setlength(f64temp, vx);
   for i := 0 to (vx-1) do
       f64temp[i] := f64in[i];
   fRawVolBytes := nil; //release
   setlength(fRawVolBytes, 4 * vx);
   f32out := TFloat32s(fRawVolBytes);
   for i := 0 to (vx-1) do
       f32out[i] := f64temp[i];
  end;
  fHdr.datatype := kDT_FLOAT32;
  fHdr.bitpix:= 32;
end;

procedure TNIfTI.InitFloat32(); //kDT_FLOAT
const
 kMaxBin = 4095;
function boundFloat(v: single): integer; inline;
begin
     if v <= 0 then exit(0);
     if v >= 4095 then exit(4095);
     result := round(v);
end;
var
  vol32: TFloat32s;
  thresh, sum, i,vx: integer;
  mn : Single = 1.0 / 0.0;
  mx : Single = (- 1.0) / (0.0);
  slope: single;
  histo: array[0..kMaxBin] of integer;
begin
  vol32 := TFloat32s(fRawVolBytes);
  //vx := (fHdr.dim[1]*fHdr.dim[2]*fHdr.dim[3]*fVolumesLoaded);
  vx := (fHdr.dim[1]*fHdr.dim[2]*fHdr.dim[3]);
  for i := 0 to (vx-1) do begin
     if (specialsingle(vol32[i])) then vol32[i] := 0.0;
     vol32[i] := (vol32[i] * fHdr.scl_slope) + fHdr.scl_inter;
     if vol32[i] < mn then
        mn := vol32[i];
     if vol32[i] > mx then
        mx := vol32[i];
  end;
  //robustMinMax(mn,mx);
  fMin := mn;
  fMax := mx;
  slope := kMaxBin / (mx - mn);
  printf(format('float range %g..%g',[mn,mx]));
  for i := 0 to kMaxBin do
      histo[i] := 0;
  for i := 0 to (vx-1) do begin
      inc(histo[ boundFloat((vol32[i]-mn) * slope)]);
  end;
  thresh := round(0.01 * vx);
  sum := 0;
  for i := 0 to kMaxBin do begin
      sum := sum + histo[i];
      if (sum > thresh) then break;
  end;
  fAutoBalMin := (i * 1/slope) + mn;
  sum := 0;
  for i := kMaxBin downto 0 do begin
      sum := sum + histo[i];
      if (sum > thresh) then break;
  end;
  fAutoBalMax := (i * 1/slope) + mn;
  if (fAutoBalMax = fAutoBalMin) then
     fAutoBalMax := ((i+1) * 1/slope) + mn;
  printf(format('float window %g...%g', [ fAutoBalMin, fAutoBalMax]));
end;

procedure TNIfTI.initInt16(); //kDT_SIGNED_SHORT
const
 kMaxBin = 4095;
function boundFloat(v: single): integer; inline;
begin
    if v <= 0 then exit(0);
    if v >= 4095 then exit(4095);
    result := round(v);
end;
var
  vol16: TInt16s;
  histo: array[0..kMaxBin] of integer;
  i, vx,mn,mx, thresh, sum: integer;
  slope: single;
begin
  for i := 0 to kMaxBin do
      histo[i] := 0;
  vol16 := TInt16s(fRawVolBytes);
  mn := vol16[0];
  mx := mn;
  //vx := (fHdr.dim[1]*fHdr.dim[2]*fHdr.dim[3]*fVolumesLoaded);
  vx := (fHdr.dim[1]*fHdr.dim[2]*fHdr.dim[3]);
  for i := 0 to (vx-1) do begin
      if vol16[i] < mn then
         mn := vol16[i];
      if vol16[i] > mx then
         mx := vol16[i];
  end;
  fMin := mn;
  fMax := mx;
  //robustMinMax(fMin,fMax);
  mn := round(fMin);
  mx := round(fMax);
  fMin := (mn * fHdr.scl_slope) + fHdr.scl_inter;
  fMax := (mx * fHdr.scl_slope) + fHdr.scl_inter;
  printf(format('int16 range %g...%g', [ fMin, fMax]));
  slope := kMaxBin / (mx - mn) ;
  for i := 0 to kMaxBin do
      histo[i] := 0;
  for i := 0 to (vx-1) do
      inc(histo[ boundFloat((vol16[i]-mn) * slope)]);
  thresh := round(0.01 * vx);
  sum := 0;
  for i := 0 to kMaxBin do begin
      sum := sum + histo[i];
      if (sum > thresh) then break;
  end;
  fAutoBalMin := (i * 1/slope) + mn;
  sum := 0;
  for i := kMaxBin downto 0 do begin
      sum := sum + histo[i];
      if (sum > thresh) then break;
  end;
  fAutoBalMax := (i * 1/slope) + mn;
  if (fAutoBalMax = fAutoBalMin) then
     fAutoBalMax := ((i+1) * 1/slope) + mn;
  fAutoBalMin := (fAutoBalMin * fHdr.scl_slope) + fHdr.scl_inter;
  fAutoBalMax := (fAutoBalMax * fHdr.scl_slope) + fHdr.scl_inter;
  printf(format('int16 window %g...%g', [ fAutoBalMin, fAutoBalMax]));
end;

function Scaled2RawIntensity (lHdr: TNIFTIhdr; lScaled: single): single;
begin
  if lHdr.scl_slope = 0 then
	result := (lScaled)-lHdr.scl_inter
  else
	result := (lScaled-lHdr.scl_inter) / lHdr.scl_slope;
end;


procedure TNIfTI.RemoveHaze();
const
 kOtsuLevels = 5;
var
   mni, i,vx, skipVx: integer;
   vol8, out8: TUInt8s;
   vol16: TInt16s;
   vol32: TFloat32s;
   mn: single;
begin
  vx := (fHdr.dim[1]*fHdr.dim[2]*fHdr.dim[3]);
  if vx < 1 then exit;
  vol8 := DisplayMinMax2Uint8;
  if vol8 = nil then exit;
  skipVx := skipVox();
  ApplyOtsuBinary (vol8, vx, kOtsuLevels);
  PreserveLargestCluster(vol8, fHdr.dim[1], fHdr.dim[2], fHdr.dim[3],255,0 );
  SimpleMaskDilate(vol8, fHdr.dim[1], fHdr.dim[2], fHdr.dim[3]);
  SimpleMaskDilate(vol8, fHdr.dim[1], fHdr.dim[2], fHdr.dim[3]);
  out8 := fRawVolBytes;
  vol16 := TInt16s(out8);
  vol32 := TFloat32s(out8);
  mn := Scaled2RawIntensity(fHdr, fMin);
  mni := round(mn);
  if fHdr.datatype = kDT_UINT8 then begin
     for i := 0 to (vx-1) do
         if vol8[i] = 0 then out8[skipVx+i] := 0;
  end else if fHdr.datatype = kDT_INT16 then begin
    for i := 0 to (vx-1) do
        if vol8[i] = 0 then vol16[skipVx+i] := mni;
  end else if fHdr.datatype = kDT_FLOAT then begin
    for i := 0 to (vx-1) do
        if vol8[i] = 0 then vol32[skipVx+i] := mn;
  end;
  vol8 := nil;//free
  SetDisplayMinMax(true);
end;

procedure TNIfTI.SetDisplayMinMaxRGB24();
var
   skipVx, i, vx: integer;
   vol24: TRGBs;
begin
  vol24 := TRGBs(fRawVolBytes);
  vx := (fHdr.dim[1]*fHdr.dim[2]*fHdr.dim[3]);
  skipVx := skipVox();
  for i := 0 to (vx - 1) do begin
    fVolRGBA[i] := SetRGBA(vol24[skipVx+i].r,vol24[skipVx+i].g,vol24[skipVx+i].b,vol24[skipVx+i].g);
  end;
end;

function setUnitRange(s: single): single;
begin
     if s < 0 then s := 0;
     if s > 1 then s := 1;
     result := s;
end;

procedure sortVec3(var lo, hi: TVec3);
var
   temp: TVec3;
   i: integer;
begin
     temp := hi;
     for i := 0 to 2 do begin
         if (hi[i] < lo[i]) then begin
            hi[i]:= lo[i];
            lo[i] := temp[i];
         end;
         lo[i] := setUnitRange(lo[i]);
         hi[i] := setUnitRange(hi[i]);
     end;
end;

procedure TNIfTI.ApplyCutout();
var
  x, y, z, xMn, yMn, zMn, xMx, yMx, zMx, dX, dXY: integer;
  clr: TRGBA;
begin
 if (fCutoutLow.X = fCutoutHigh.X) or (fCutoutLow.Y = fCutoutHigh.Y) or (fCutoutLow.Z = fCutoutHigh.Z) then exit;
 if not HiddenByCutout then exit;
 sortVec3(fCutoutLow, fCutoutHigh);
 xMn := round((fHdr.dim[1]-1)*fCutoutLow.x);
 yMn := round((fHdr.dim[2]-1)*fCutoutLow.y);
 zMn := round((fHdr.dim[3]-1)*fCutoutLow.z);
 xMx := round((fHdr.dim[1]-1)*fCutoutHigh.x);
 yMx := round((fHdr.dim[2]-1)*fCutoutHigh.y);
 zMx := round((fHdr.dim[3]-1)*fCutoutHigh.z);
 if (xMx <= xMn) or (yMx <= yMn) or (zMx <= zMn) then exit;
 dX := fHdr.dim[1];
 dXY := fHdr.dim[1] * fHdr.dim[2];
 clr := setRGBA(0,0,0,0);
 if (length(fVolRGBA) < 1) and (DisplayMin < 0) and (DisplayMax < 0) then begin
    if (length(fCache8) < 1) then exit;
    for z := zMn to zMx do
        for y := yMn to yMx do
            for x := xMn to xMx do
                fCache8[x + (y*dX) + (z * dXY)] := 255;
    exit;
 end;
 if (length(fVolRGBA) < 1) then begin
    if (length(fCache8) < 1) then exit;
    for z := zMn to zMx do
        for y := yMn to yMx do
            for x := xMn to xMx do
                fCache8[x + (y*dX) + (z * dXY)] := 0;
    exit;
 end;
 for z := zMn to zMx do
     for y := yMn to yMx do
         for x := xMn to xMx do
             fVolRGBA[x + (y*dX) + (z * dXY)] := clr;
end;

function TNIfTI.NeedsUpdate(): boolean;
begin
     result := true;
     if (not clut.NeedsUpdate) and (fHdr.datatype <> kDT_RGB) and (fCache8 <> nil) and (not specialsingle(fWindowMinCache8)) and (fOpacityPct = fOpacityPctCache8) and (fWindowMin = fWindowMinCache8) and (fWindowMax = fWindowMaxCache8) then
        result := false;
end;

procedure TNIfTI.DisplayLabel2Uint8();
var
   skipVx, v, vx: integer;
   vol8: TUInt8s;
   vol16: TInt16s;
begin
 vx := (fHdr.dim[1]*fHdr.dim[2]*fHdr.dim[3]);
 setlength(fCache8, vx);
 vol8 := fRawVolBytes;
 skipVx := skipVox();
 if fHdr.datatype = kDT_INT16 then begin //16 bit data
   vol16 := TInt16s(vol8);
   for v := 0 to (vx-1) do
       fCache8[v] := ((vol16[v+skipVx]-1) mod 100)+1;//lCLUT8[((lTexture.RawUnscaledImg16^[lVox]-1) mod 100)+1];
 end else begin
       for v := 0 to (vx-1) do
            fCache8[v] := vol8[v+skipVx];
   end; //if 16bit else 8bit
end;

function TNIfTI.DisplayMinMax2Uint8(isForceRefresh: boolean = false): TUInt8s;
var
  slope, lMin, lMax, lSwap, lRng, lMod: single;
  skipVx, i, j, vx: integer;
  vol8:TUInt8s;
  vol16: TInt16s;
  vol32: TFloat32s;
  luts: array[0..255] of byte;
begin
  if (fHdr.datatype = kDT_RGB) then exit(nil);
  vx := (fHdr.dim[1]*fHdr.dim[2]*fHdr.dim[3]);
  if vx < 1 then exit(nil);
  if (not isForceRefresh) and (not NeedsUpdate) then// (not clut.NeedsUpdate) and (fHdr.datatype <> kDT_RGB) and (fCache8 <> nil) and (fWindowMinCache8 <> fWindowMaxCache8) and (fWindowMin = fWindowMinCache8) and (fWindowMax = fWindowMaxCache8) then begin
     exit(fCache8);
  vol8 := fRawVolBytes;
  skipVx := SkipVox();
  if (IsLabels()) then begin
    //DisplayLabel2Uint8();
    clut.GenerateLUT(abs(fWindowMax-fWindowMin)/100);
    result := fCache8;
    fWindowMinCache8 := fWindowMin;
    fWindowMaxCache8 := fWindowMax;
    fOpacityPctCache8 := fOpacityPct;
    clut.NeedsUpdate := false;
    exit;
  end;
  setlength(fCache8, vx);
  lMin := Scaled2RawIntensity(fHdr, fWindowMin);
  lMax := Scaled2RawIntensity(fHdr, fWindowMax);
  slope := 255/(lMax - lMin);
  vol16 := TInt16s(vol8);
  vol32 := TFloat32s(vol8);
  if fHdr.datatype = kDT_UINT8 then begin
    lRng := (lMax - lMin);
    if lRng <> 0 then
     lMod := abs((((254)/lRng)))
    else
      lMod := 0;
    if lMin > lMax then begin
         lSwap := lMin;
         lMin := lMax;
         lMax := lSwap;
    end;
    for i := 0 to 255 do begin
      if i <= lMin then
        j := 0
      else if i >= lMax then
          j := 255
      else
         j := trunc(((i-lMin)*lMod)+1);
      luts[i] := j;
    end;
    for i := 0 to (vx - 1) do
        fCache8[i] := luts[vol8[skipVx+i]];
  end else if fHdr.datatype = kDT_INT16 then begin
    for i := 0 to (vx - 1) do begin
      if (vol16[skipVx+i] >= lMax) then
         j := 255
      else if  (vol16[skipVx+i] <= lMin) then
          j := 0
      else
         j := round((vol16[skipVx+i] - lMin) * slope);
      fCache8[i] := j;
    end;
  end else if fHdr.datatype = kDT_FLOAT then begin
    for i := 0 to (vx - 1) do begin
      if (vol32[skipVx+i] >= lMax) then
         j := 255
      else if  (vol32[skipVx+i] <= lMin) then
          j := 0
      else
         j := round((vol32[skipVx+i] - lMin) * slope);
      fCache8[i] := j;
    end;
  end;
  result := fCache8;
  fWindowMinCache8 := fWindowMin;
  fWindowMaxCache8 := fWindowMax;
  fOpacityPctCache8 := fOpacityPct;
  clut.NeedsUpdate := false;
  ApplyCutout();
end;

procedure TNIfTI.SetDisplayMinMax(isForceRefresh: boolean = false); overload;
var
  i, vx: integer;
begin
  if (fIsOverlay) then exit; //overlays visualized using DisplayMinMax2Uint8
  vx := (fHdr.dim[1]*fHdr.dim[2]*fHdr.dim[3]);
  if (vx < 1) then exit;
  if (not isForceRefresh) and (not NeedsUpdate) then //(not clut.NeedsUpdate) and (fHdr.datatype <> kDT_RGB) and (fCache8 <> nil) and (fWindowMinCache8 <> fWindowMaxCache8) and (fWindowMin = fWindowMinCache8) and (fWindowMax = fWindowMaxCache8) then
     exit; //no change
  if fHdr.datatype = kDT_RGB then begin
    setlength(fVolRGBA, vx);
    SetDisplayMinMaxRGB24();
    ApplyCutout();
    exit;
  end;
  printf(format('Window %g..%g', [fWindowMin, fWindowMax]));
  DisplayMinMax2Uint8(isForceRefresh);
  setlength(fVolRGBA, vx);
  for i := 0 to (vx - 1) do
     {$IFDEF CUSTOMCOLORS}
     fVolRGBA[i] := clut.LUT[fCache8[i]];
     {$ELSE}
     fVolRGBA[i] := fLUT[fCache8[i]];
     {$ENDIF}
  ApplyCutout();
end;

procedure TNIfTI.SetCutoutNoUpdate(CutoutLow, CutoutHigh: TVec3);
begin
     fCutoutLow := CutoutLow;
     fCutoutHigh := CutoutHigh;
     {$IFDEF CACHEUINT8}
      fWindowMinCache8 := infinity;
     {$ENDIF}
end;

procedure TNIfTI.SetDisplayVolume(newDisplayVolume: integer);
var
  //i,
  n: integer;
begin
   //i := newDisplayVolume;
   if (fIsOverlay) then
      n := fHdr.dim[4]
   else
      n := fVolumesLoaded;
  if (newDisplayVolume < 0) then
     newDisplayVolume := n - 1;
  if (newDisplayVolume >= n)  then
     newDisplayVolume := 0;
  if newDisplayVolume = fVolumeDisplayed  then exit;
  fVolumeDisplayed := newDisplayVolume;
  if not fIsOverlay then begin
     {$IFDEF CACHEUINT8} //force refresh
     fWindowMinCache8 := infinity;
     {$ENDIF}
     SetDisplayMinMax(); //refresh RGBA
     exit;
  end;
  //following for overlays, which we load one at a time, and often need to reslice...
  //close old image
  fLabels.clear;
  //fRawVolBytes := nil;
  //fVolRGBA := nil;
  fCache8 := nil;
  {$IFDEF CUSTOMCOLORS}
  //clut := nil;
  {$ENDIF}
  Load(fFileName, fMat, fDim, false, fVolumeDisplayed, true); //isKeepContrast
end;

procedure TNIfTI.SetDisplayColorScheme(clutFileName: string; cTag: integer);
begin
 {$IFDEF CUSTOMCOLORS}
 CLUT.OpenCLUT(clutFileName, cTag);
 if (CLUT.SuggestedMinIntensity < CLUT.SuggestedMaxIntensity) and (fMax > CLUT.SuggestedMinIntensity) and (fMin < CLUT.SuggestedMaxIntensity) then begin
    fWindowMin := CLUT.SuggestedMinIntensity;
    fWindowMax := CLUT.SuggestedMaxIntensity;
 end;
 {$IFDEF CACHEUINT8} //force refresh
  fWindowMinCache8 := infinity;
 {$ENDIF}
 SetDisplayMinMax(); //refresh RGBA
 {$ENDIF}
end;

procedure TNIfTI.SetDisplayMinMaxNoUpdate(newMin, newMax: single); overload;
begin
 if newMin > newMax then begin
    fWindowMin := newMax;
    fWindowMax := newMin;
 end else begin
     fWindowMin := newMin;
     fWindowMax := newMax;
 end;
end;

procedure TNIfTI.SetDisplayMinMax(newMin, newMax: single); overload;
begin
 SetDisplayMinMaxNoUpdate(newMin, newMax);
 SetDisplayMinMax;
end;

{$IFDEF GZIP}
function LoadImgGZ(FileName : AnsiString; swapEndian: boolean; var  rawData: TUInt8s; var lHdr: TNIFTIHdr): boolean;
//foreign: both image and header compressed
var
  Stream: TGZFileStream;
  volBytes: int64;
begin
 result := false;
 Stream := TGZFileStream.Create (FileName, gzopenread);
 Try
  if (lHdr.bitpix <> 8) and (lHdr.bitpix <> 16) and (lHdr.bitpix <> 24) and (lHdr.bitpix <> 32) and (lHdr.bitpix <> 64) then begin
   printf('Unable to load '+Filename+' - this software can only read 8,16,24,32,64-bit NIfTI files.');
   exit;
  end;
  //read the image data
  volBytes := lHdr.Dim[1]*lHdr.Dim[2]*lHdr.Dim[3] * (lHdr.bitpix div 8);
  if lHdr.dim[4] > 1 then
    volBytes := volBytes * lHdr.dim[4];
  Stream.Seek(round(lHdr.vox_offset),soFromBeginning);
  SetLength (rawData, volBytes);
  Stream.ReadBuffer (rawData[0], volBytes);
  if swapEndian then
   SwapImg(rawData, lHdr.bitpix);
 Finally
  Stream.Free;
 End;
 result := true;
end;

function LoadHdrRawImgGZ(FileName : AnsiString; swapEndian: boolean; var  rawData: TUInt8s; var lHdr: TNIFTIHdr): boolean;
var
   Stream: TFileStream;
   volBytes: integer;
   inStream, outStream : TMemoryStream;
label
     123;
begin
 result := false;
 if not fileexists(Filename) then exit;
 if (lHdr.bitpix <> 8) and (lHdr.bitpix <> 16) and (lHdr.bitpix <> 24) and (lHdr.bitpix <> 32) and (lHdr.bitpix <> 64) then begin
   printf('Unable to load '+Filename+' - this software can only read 8,16,24,32,64-bit NIfTI files.');
   exit;
 end;
 Stream := TFileStream.Create(Filename, fmOpenRead);
 inStream := TMemoryStream.Create();
 outStream := TMemoryStream.Create();
 Stream.seek(round(lHdr.vox_offset), soFromBeginning);
 inStream.CopyFrom(Stream, Stream.Size - round(lHdr.vox_offset));
 result := unzipStream(inStream, outStream);
 if not result then goto 123;
 volBytes := lHdr.Dim[1]*lHdr.Dim[2]*lHdr.Dim[3] * (lHdr.bitpix div 8);
 if lHdr.dim[4] > 1 then
   volBytes := volBytes * lHdr.dim[4];
 if outStream.Size < volBytes then begin
    result := false;
    goto 123;
 end;
 SetLength (rawData, volBytes);
 outStream.ReadBuffer (rawData[0], volBytes);
 if swapEndian then
   SwapImg(rawData, lHdr.bitpix);
 123:
   inStream.Free;
   outStream.Free;
   Stream.Free;
end;

{$ENDIF}

function loadForeign(FileName : AnsiString; var  rawData: TUInt8s; var lHdr: TNIFTIHdr): boolean;// Load 3D data                                 }
//Uncompressed .nii or .hdr/.img pair
var
   Stream : TFileStream;
   gzBytes, volBytes: int64;
   swapEndian, isDimPermute2341: boolean;
begin
 result := readForeignHeader (FileName, lHdr,  gzBytes, swapEndian, isDimPermute2341);
 if not result then exit;
 if (lHdr.bitpix <> 8) and (lHdr.bitpix <> 16) and (lHdr.bitpix <> 24) and (lHdr.bitpix <> 32) and (lHdr.bitpix <> 64) then begin
  printf('Unable to load '+Filename+' - this software can only read 8,16,24,32,64-bit NIfTI files.');
  exit;
 end;
 if gzBytes = K_gzBytes_onlyImageCompressed then begin
   result := LoadHdrRawImgGZ(FileName, swapEndian,  rawData, lHdr);
   exit;
   //{$IFNDEF Windows} writeln('Unsupported format: foreign uncompressed header, compressed image ', gzBytes);{$ENDIF}
   //exit(false);
 end else if gzBytes < 0 then begin
   //{$IFNDEF Windows} writeln('foreign compressed header and image ', gzBytes);{$ENDIF}
    result := LoadImgGZ(FileName, swapEndian,  rawData, lHdr);
    exit;
 end;
 Stream := TFileStream.Create (FileName, fmOpenRead or fmShareDenyWrite);
 Try
  Stream.Seek(round(lHdr.vox_offset),soFromBeginning);
  volBytes := lHdr.Dim[1]*lHdr.Dim[2]*lHdr.Dim[3] * (lHdr.bitpix div 8);
  if lHdr.dim[4] > 1 then
    volBytes := volBytes * lHdr.dim[4];
  SetLength (rawData, volBytes);
  Stream.ReadBuffer (rawData[0], volBytes);
  if swapEndian then
   SwapImg(rawData, lHdr.bitpix);
 Finally
  Stream.Free;
 End;
 result := true;
end;

function TNIfTI.OpenNIfTI(): boolean;
var
   F_Filename,lExt: string;
begin
 result := false;
 if (length(fFilename) < 1) or (not FileExists(fFilename)) then exit;
 fVolumesLoaded := 1;
 lExt := uppercase(extractfileext(fFilename));
 if lExt = '.IMG' then begin
   //NIfTI images can be a single .NII file [contains both header and image]
   //or a pair of files named .HDR and .IMG. If the latter, we want to read the header first
   F_Filename := changefileext(fFilename,'.hdr');
   {$IFDEF LINUX} //LINUX is case sensitive, OSX is not
   printf('Unable to find header (case sensitive!) '+F_Filename);
   {$ELSE}
   printf('Unable to find header '+F_Filename);
   {$ENDIF}
   lExt := uppercase(extractfileext(F_Filename));
 end else
   F_Filename := fFilename;
 fKnownOrientation := false;
 {$IFDEF GZIP}
 if (lExt = '.MAT') then begin
    result := MatLoadNii(F_FileName, fHdr, fRawVolBytes);
    exit;
 end;
 {$ENDIF}
 if (lExt <> '.IMG') and (lExt <> '.NII') and (lExt <> '.VOI') and  (lExt <> '.HDR') and (lExt <> '.GZ') then begin
    result := loadForeign(F_FileName, fRawVolBytes, fHdr);
    if result then begin
       fVolumesLoaded := length(fRawVolBytes) div (fHdr.Dim[1]*fHdr.Dim[2]*fHdr.Dim[3] * (fHdr.bitpix div 8));
    end;
    exit;
 end;
 if (lExt = '.GZ') or (lExt = '.VOI') then begin
   {$IFDEF GZIP}
   if not LoadGZ(F_FileName, fIsNativeEndian) then
      exit;
   {$ELSE}
   Showdebug('Please manually decompress images '+F_Filename);
   exit;
   {$ENDIF}
 end else if not (result) then begin
   //fVolumeDisplayed := 0;
   if not LoadRaw(F_FileName, fIsNativeEndian) then begin
     exit(false);
   end;
 end;
 if (fHdr.sform_code > kNIFTI_XFORM_UNKNOWN) or (fHdr.qform_code > kNIFTI_XFORM_UNKNOWN) then
    fKnownOrientation := true
 else
    NoMat(fHdr);
 fBidsName := changefileextX(F_FileName,'.json'); //file.nii.gz -> file.txt
 if not Fileexists(fBidsName) then
    fBidsName := '';
 result := true;
end;

{$DEFINE OVERLAY}
{$IFDEF OVERLAY}
procedure  Coord(var lV: TVec3; lMat: TMat4);
//transform X Y Z by matrix
var
  lXi,lYi,lZi: single;
begin
  lXi := lV.x; lYi := lV.y; lZi := lV.z;
  lV.x := (lXi*lMat[0,0]+lYi*lMat[0,1]+lZi*lMat[0,2]+lMat[0,3]);
  lV.y := (lXi*lMat[1,0]+lYi*lMat[1,1]+lZi*lMat[1,2]+lMat[1,3]);
  lV.z := (lXi*lMat[2,0]+lYi*lMat[2,1]+lZi*lMat[2,2]+lMat[2,3]);
end;

function matrix3D(a,b,c,d, e,f,g,h, i,j,k,l: single): TMat4;
begin
     result := TMat4.Identity;
     result[0,0] := a;
     result[0,1] := b;
     result[0,2] := c;
     result[0,3] := d;
     result[1,0] := e;
     result[1,1] := f;
     result[1,2] := g;
     result[1,3] := h;
     result[2,0] := i;
     result[2,1] := j;
     result[2,2] := k;
     result[2,3] := l;
end;  //matrix3D()

function mStr(prefix: string; m: TMat4): string;
begin
    result := format('%s = [%g %g %g %g; %g %g %g %g; %g %g %g %g; %g %g %g %g]; ', [prefix,
      m[0,0], m[0,1],m[0,2],m[0,3],
      m[1,0], m[1,1],m[1,2],m[1,3],
      m[2,0], m[2,1],m[2,2],m[2,3],
      m[3,0], m[3,1],m[3,2],m[3,3]]);
end; //

function Voxel2Voxel (lDestMat, lSrcMat: TMat4): TMat4;
//returns matrix for transforming voxels from one image to the other image
//results are in VOXELS not mm
var
   lV0,lVx,lVy,lVz: TVec3;
   lSrcMatInv: TMat4;

begin
     //Step 1 - compute source coordinates in mm for 4 voxels
     //the first vector is at 0,0,0, with the
     //subsequent voxels being left, up or anterior
     //lDestMat := Hdr2Mat(lDestHdr);
     lV0 := Vec3( 0,0,0);
     lVx := Vec3( 1,0,0);
     lVy := Vec3( 0,1,0);
     lVz := Vec3( 0,0,1);
     Coord(lV0,lDestMat);
     Coord(lVx,lDestMat);
     Coord(lVy,lDestMat);
     Coord(lVz,lDestMat);
     lSrcMatInv := lSrcMat.inverse;
     //clipboard.AsText := mStr('i2',lSrcMatInv);
     //the vectors should be rows not columns....
     //therefore we transpose the matrix
     //lSrcMatInv := lSrcMatInv.transpose;
     //the 'transform' multiplies the vector by the matrix
     lV0 := (lV0 * lSrcMatInv);
     lVx := (lVx * lSrcMatInv);
     lVy := (lVy * lSrcMatInv);
     lVz := (lVz * lSrcMatInv);
     //subtract each vector from the origin
     // this reveals the voxel-space influence for each dimension
     lVx := lVx - lV0;
     lVy := lVy - lV0;
     lVz := lVz - lV0;
     result := Matrix3D(lVx.x,lVy.x,lVz.x,lV0.x,
      lVx.y,lVy.y,lVz.y,lV0.y,
      lVx.z,lVy.z,lVz.z,lV0.z);
end;

procedure TNIfTI.VolumeReslice(tarMat: TMat4; tarDim: TVec3i; isLinearReslice: boolean);
var
   m: TMat4;
   in8, out8: TUInt8s;
   in16, out16: TInt16s;
   in32, out32: TInt32s;
   in32f, out32f: TFloat32s;
   lMaxY, lMaxZ, lMinY, lMinZ: integer;
   lXrM1, lYrM1, lZrM1, lZx, lZy, lZz, lYx, lYy, lYz, lXreal, lYreal, lZreal: single;
   lXx, lXy, lXz: array of single;
   lXYs, lXs, lYs, lZs, lXo, lYo, lZo, lPos,i,lXi, lYi, lZi, datatype, lBPP: integer;
   lOverlap : boolean = false;
   inVox, outvox: integer;
   minNegNotZero, minPosNotZero, minNegThresh, minPosThresh: single;
begin
     if prod(tarDim) < 1 then exit;
     if (tarMat = fMat) and (tarDim.X = fDim.X) and (tarDim.Y = fDim.Y) and (tarDim.Z = fDim.Z) then exit;
     if prod(tarDim) = prod(fDim) then begin
        VolumeReorient();
        if (tarMat = fMat) and (tarDim.X = fDim.X) and (tarDim.Y = fDim.Y) and (tarDim.Z = fDim.Z) then exit;
     end;
     if fVolumesLoaded > 1 then begin
        showmessage('Fatal error: overlays can not have multiple volumes [yet]');
        exit;
     end;
     //if isLinearReslice then
     //   SmoothMaskedImages();
     m := Voxel2Voxel (tarMat,fMat); //source to target voxels
     //clipboard.AsText := mStr('t',tarMat)+mStr('s',fMat)+mStr('vx',m);
     lXs := fDim.X;
     lYs := fDim.Y;
     lZs := fDim.Z;
     lXYs:=lXs*lYs; //slicesz
     dataType := fHdr.datatype;
     case dataType of
       kDT_UNSIGNED_CHAR : lBPP := 1;
       kDT_SIGNED_SHORT: lBPP := 2;
       kDT_SIGNED_INT:lBPP := 4;
       kDT_FLOAT: lBPP := 4;
       else begin
          printf('NII reslice error: datatype not supported.');
          exit;
       end;
     end; //case
     i := prod(fDim) * lBPP; //input bytes
     setlength(in8, i);
     in8 := Copy(fRawVolBytes, Low(fRawVolBytes), Length(fRawVolBytes));
     i := prod(tarDim) * lBPP; //target bytes
     //clipboard.AsText := format('%d %d', [prod(tarDim), lBPP]);
     setlength(fRawVolBytes,0);
     setlength(fRawVolBytes, i);
     out8 := TUInt8s(fRawVolBytes);
     for lXi := 0 to (i-1) do
         out8[lXi] := 0;

     //clipboard.AsText := format('%d %d', [prod(tarDim), lBPP]);
     in16 := TInt16s(in8);
     out16 := TInt16s(fRawVolBytes);
     in32 := TInt32s(in8);
     out32 := TInt32s(fRawVolBytes);
     in32f := TFloat32s(in8);
     out32f := TFloat32s(fRawVolBytes);
     setlength(lXx, tarDim.x);
     setlength(lXy, tarDim.x);
     setlength(lXz, tarDim.x);
     for lXi := 0 to (tarDim.x-1) do begin
      lXx[lXi] := lXi*m[0,0];
      lXy[lXi] := lXi*m[1,0];
      lXz[lXi] := lXi*m[2,0];
     end;
     lPos := -1;
     if isLinearReslice then begin //trilinear
        for lZi := 0 to (tarDim.Z-1) do begin
            //these values are the same for all voxels in the slice
            // compute once per slice
            lZx := lZi*m[0,2];
            lZy := lZi*m[1,2];
            lZz := lZi*m[2,2];
            for lYi := 0 to (tarDim.Y-1) do begin
                //these values change once per row
                // compute once per row
                lYx :=  lYi*m[0,1];
                lYy :=  lYi*m[1,1];
                lYz :=  lYi*m[2,1];
                for lXi := 0 to (tarDim.x-1) do begin
                    inc(lPos);
                    //compute each column
                    lXreal := (lXx[lXi]+lYx+lZx+m[0,3]);
                    lYreal := (lXy[lXi]+lYy+lZy+m[1,3]);
                    lZreal := (lXz[lXi]+lYz+lZz+m[2,3]);
                    //need to test Xreal as -0.01 truncates to zero
                    if (lXreal >= 0) and (lYreal >= 0{1}) and (lZreal >= 0{1}) and
                        (lXreal < (lXs -1)) and (lYreal < (lYs -1) ) and (lZreal < (lZs -1))
                     then begin
                        //compute the contribution for each of the 8 source voxels
                        //nearest to the target
                        lOverlap := true;
                        lXo := trunc(lXreal);
                        lYo := trunc(lYreal);
                        lZo := trunc(lZreal);
                        lXreal := lXreal-lXo;
                        lYreal := lYreal-lYo;
                        lZreal := lZreal-lZo;
                        lXrM1 := 1-lXreal;
                        lYrM1 := 1-lYreal;
                        lZrM1 := 1-lZreal;
                        lMinY := lYo*lXs;
                        lMinZ := lZo*lXYs;
                        lMaxY := lMinY+lXs;
                        lMaxZ := lMinZ+lXYs;
                        //inc(lXo);//if images incremented from 1 not 0
                        case dataType of
                          kDT_UNSIGNED_CHAR : begin// l8is := l8is;
                               out8[lPos] := round (
                             {all min} ( (lXrM1*lYrM1*lZrM1)*in8[lXo+lMinY+lMinZ])
                             {x+1}+((lXreal*lYrM1*lZrM1)*in8[lXo+1+lMinY+lMinZ])
                             {y+1}+((lXrM1*lYreal*lZrM1)*in8[lXo+lMaxY+lMinZ])
                             {z+1}+((lXrM1*lYrM1*lZreal)*in8[lXo+lMinY+lMaxZ])
                             {x+1,y+1}+((lXreal*lYreal*lZrM1)*in8[lXo+1+lMaxY+lMinZ])
                             {x+1,z+1}+((lXreal*lYrM1*lZreal)*in8[lXo+1+lMinY+lMaxZ])
                             {y+1,z+1}+((lXrM1*lYreal*lZreal)*in8[lXo+lMaxY+lMaxZ])
                             {x+1,y+1,z+1}+((lXreal*lYreal*lZreal)*in8[lXo+1+lMaxY+lMaxZ]) );
                          end;
                          kDT_SIGNED_SHORT: begin
                               out16[lPos] := round (
                             {all min} ( (lXrM1*lYrM1*lZrM1)*in16[lXo+lMinY+lMinZ])
                             {x+1}+((lXreal*lYrM1*lZrM1)*in16[lXo+1+lMinY+lMinZ])
                             {y+1}+((lXrM1*lYreal*lZrM1)*in16[lXo+lMaxY+lMinZ])
                             {z+1}+((lXrM1*lYrM1*lZreal)*in16[lXo+lMinY+lMaxZ])
                             {x+1,y+1}+((lXreal*lYreal*lZrM1)*in16[lXo+1+lMaxY+lMinZ])
                             {x+1,z+1}+((lXreal*lYrM1*lZreal)*in16[lXo+1+lMinY+lMaxZ])
                             {y+1,z+1}+((lXrM1*lYreal*lZreal)*in16[lXo+lMaxY+lMaxZ])
                             {x+1,y+1,z+1}+((lXreal*lYreal*lZreal)*in16[lXo+1+lMaxY+lMaxZ]) );
                          end;
                          kDT_SIGNED_INT:begin
                               out32[lPos] :=
                                round (
                             {all min} ( (lXrM1*lYrM1*lZrM1)*in32[lXo+lMinY+lMinZ])
                             {x+1}+((lXreal*lYrM1*lZrM1)*in32[lXo+1+lMinY+lMinZ])
                             {y+1}+((lXrM1*lYreal*lZrM1)*in32[lXo+lMaxY+lMinZ])
                             {z+1}+((lXrM1*lYrM1*lZreal)*in32[lXo+lMinY+lMaxZ])
                             {x+1,y+1}+((lXreal*lYreal*lZrM1)*in32[lXo+1+lMaxY+lMinZ])
                             {x+1,z+1}+((lXreal*lYrM1*lZreal)*in32[lXo+1+lMinY+lMaxZ])
                             {y+1,z+1}+((lXrM1*lYreal*lZreal)*in32[lXo+lMaxY+lMaxZ])
                             {x+1,y+1,z+1}+((lXreal*lYreal*lZreal)*in32[lXo+1+lMaxY+lMaxZ]) );
                          end;
                          kDT_FLOAT: begin
                               out32f[lPos] :=
                                 (
                             {all min} ( (lXrM1*lYrM1*lZrM1)*in32f[lXo+lMinY+lMinZ])
                             {x+1}+((lXreal*lYrM1*lZrM1)*in32f[lXo+1+lMinY+lMinZ])
                             {y+1}+((lXrM1*lYreal*lZrM1)*in32f[lXo+lMaxY+lMinZ])
                             {z+1}+((lXrM1*lYrM1*lZreal)*in32f[lXo+lMinY+lMaxZ])
                             {x+1,y+1}+((lXreal*lYreal*lZrM1)*in32f[lXo+1+lMaxY+lMinZ])
                             {x+1,z+1}+((lXreal*lYrM1*lZreal)*in32f[lXo+1+lMinY+lMaxZ])
                             {y+1,z+1}+((lXrM1*lYreal*lZreal)*in32f[lXo+lMaxY+lMaxZ])
                             {x+1,y+1,z+1}+((lXreal*lYreal*lZreal)*in32f[lXo+1+lMaxY+lMaxZ]) );
                          end;
                      end; //case of datatype

                    end; //if voxel is in source image's bounding box
                end;//z
            end;//y
        end;//z
        //handle intepolation of thresholded 32-bit data
        if (dataType = kDT_FLOAT) then begin
           //consider data thresholded at z > 3.0: do not allow interpolated values below this!
           // values 0..1.5 will be set to zero, values 1.5..3 will be set to 3
          inVox := prod(fDim);
          outVox := prod(tarDim);
          minPosNotZero := infinity;
          for i := 0 to (inVox-1) do
              if (in32f[i] > 0) and (in32f[i] <  minPosNotZero) then
                 minPosNotZero := in32f[i]; //closest positive to zero
          minNegNotZero := -infinity;
          for i := 0 to (inVox-1) do
              if (in32f[i] < 0) and (in32f[i] >  minNegNotZero) then
                 minNegNotZero := in32f[i]; //closest negative to zero
          minNegThresh := minNegNotZero * 0.5;
          minPosThresh := minPosNotZero * 0.5;
          for i := 0 to (outVox-1) do
              if (out32f[i] < 0) and (out32f[i] >  minNegNotZero) then begin
                 if out32f[i] > minNegThresh then
                    out32f[i] := 0
                 else
                     out32f[i] := minNegNotZero; //closest negative to zero
              end;
          for i := 0 to (outVox-1) do
              if (out32f[i] > 0) and (out32f[i] <  minPosNotZero) then begin
                 if out32f[i] < minPosThresh then
                    out32f[i] := 0
                 else
                     out32f[i] := minPosNotZero; //closest negative to zero
              end;
        end;
     end else begin //if trilinear, else nearest neighbor
        for lZi := 0 to (tarDim.Z-1) do begin
          //these values are the same for all voxels in the slice
          // compute once per slice
            lZx := lZi*m[0,2];
            lZy := lZi*m[1,2];
            lZz := lZi*m[2,2];
            for lYi := 0 to (tarDim.Y-1) do begin
               //these values change once per row
               // compute once per row
               lYx :=  lYi*m[0,1];
               lYy :=  lYi*m[1,1];
               lYz :=  lYi*m[2,1];
               for lXi := 0 to (tarDim.X-1) do begin
                   //compute each column
                   inc(lPos);
                   lXo := round(lXx[lXi]+lYx+lZx+m[0,3]);
                   lYo := round(lXy[lXi]+lYy+lZy+m[1,3]);
                   lZo := round(lXz[lXi]+lYz+lZz+m[2,3]);
                   if (lXo >= 0) and (lYo >= 0{1}) and (lZo >= 0{1}) and
                       (lXo < (lXs -1)) and (lYo < (lYs -1) ) and (lZo < (lZs {-1}))
                    then begin
                      lOverlap := true;
                      //inc(lXo);//if images incremented from 1 not 0
                      lYo := lYo*lXs;
                      lZo := lZo*lXYs;
                      case dataType of
                        kDT_UNSIGNED_CHAR : // l8is := l8is;
                        out8[lPos] :=in8[lXo+lYo+lZo];
                        kDT_SIGNED_SHORT: out16[lPos] := in16[lXo+lYo+lZo];
                        kDT_FLOAT,kDT_SIGNED_INT: out32[lPos] := in32[lXo+lYo+lZo];
                      // kDT_FLOAT: out32f[lPos] := in32f[lXo+lYo+lZo];
                      end; //case
                   end; //if voxel is in source image's bounding box
               end;//z
            end;//y
        end;//z
     end; //if trilinear else nearest
     fMat := tarMat;
     fDim := tarDim;
     fhdr.dim[1] := tarDim.x;
     fhdr.dim[2] := tarDim.y;
     fhdr.dim[3] := tarDim.z;
     Mat2SForm(tarMat, fHdr);
     if not lOverlap then
        printf('Warning no overlap between overlay and background volume');
end;

{$ELSE}
procedure TNIfTI.VolumeReslice(tarMat: TMat4; tarDim: TVec3i);
begin
     printf('Recompile with reslice support!');
end;

{$ENDIF}

procedure LoadLabelsCore(lInStr: string; var lLabels: TStringList);
const
  kTab = chr(9);
  //kEsc = chr(27);
  kCR = chr (13);
  //kBS = #8 ; // Backspace
  //kDel = #127 ; // Delete
  kUNIXeoln = chr(10);
var
   lIndex,lPass,lMaxIndex,lPos,lLength: integer;
   lStr1: string;
   lCh: char;
begin
     lLabels.Clear;
     lLength := length(lInStr);
     lMaxIndex := -1;
     for lPass := 1 to 2 do begin
      lPos := 1;
      if lPass = 2 then begin
        if lMaxIndex < 1 then
          exit;
        for lIndex := 0 to lMaxIndex do
          lLabels.Add('');
      end;
      while lPos <= lLength do begin
        lStr1 := '';
        repeat
	             lCh := lInStr[lPos]; inc(lPos);
	             if (lCh >= '0') and (lCh <= '9') then
		        lStr1 := lStr1 + lCh;
        until (lPos > lLength) or (lCh = kCR) or (lCh = kUNIXeoln) or (((lCh = kTab)or (lCh=' ')) and (length(lStr1)>0));
        if (length(lStr1) > 0) and (lPos <= lLength) then begin
		      lIndex := strtoint(lStr1);
          if lPass = 1 then begin
                      if lIndex > lMaxIndex then
                         lMaxIndex := lIndex
          end else if lIndex >= 0 then begin //pass 2
            lStr1 := '';
		        repeat
              lCh := lInStr[lPos]; inc(lPos);
              if (lPos > lLength) or (lCh=kCR) or (lCh=kUNIXeoln) {or (lCh=kTab) or (lCh=' ')} then
                  //
              else
                lStr1 := lStr1 + lCh;
            until (lPos > lLength) or (lCh=kCR) or (lCh=kUNIXeoln) {or (lCh=kTab)or (lCh=' ')};
			      lLabels[lIndex] := lStr1;
		      end; //if pass 2
		    end; //if lStr1>0
	    end; //while not EOF
     end; //for each pass
end;

procedure LoadLabels(lFileName: string; var lLabels: TStringList; lOffset,lLength: integer);
var
  f : file; // untyped file
  s, lExt : string; // string for reading a file
  sz: int64;
  ptr: bytep;
begin
 lExt := uppercase(extractfileext(lFileName));
 if (lExt = '.GZ') or (lExt = '.VOI') then begin  //save gz compressed
    if (lLength < 1) then exit;
    SetLength(s, lLength);
    ptr :=  @s[1];
    UnGZip (lFileName,ptr, lOffset,lLength);
  end else begin
    AssignFile(f, lFileName);
    FileMode := fmOpenRead;
    reset(f, 1);
    if lOffset > 0 then
      seek(f, lOffset);
    if (lLength < 1) then
      sz := FileSize(f)-lOffset
    else
      sz := lLength;
    if (lOffset+sz) > FileSize(f) then
      exit;
    SetLength(s, sz);
    BlockRead(f, s[1], length(s));
    CloseFile(f);
    FileMode := fmOpenReadWrite;
   end;
   LoadLabelsCore(s, lLabels);
   //showmessage(lLabels[1]);
end;

procedure LoadLabelsTxt(lFileName: string; var lLabels: TStringList);
//filename = 'all.nii' will read 'aal.txt'
var
   lLUTname: string;
begin
     lLabels.Clear; //empty current labels
     lLUTname := changefileextX(lFileName,'.txt'); //file.nii.gz -> file.txt
     if not Fileexists(lLUTname) then
        lLUTname := changefileext(lFileName,'.txt'); //file.nii.gz -> file.nii.txt ;
     if not Fileexists(lLUTname) then
        exit;
     LoadLabels(lLUTname, lLabels,0,-1);
end;

procedure fixBogusHeaders(var h: TNIFTIhdr);
var
   isBogus : boolean = false;
   i: integer;
procedure checkSingle(var f: single);
begin
 if (specialSingle(f)) or (f = 0.0) then begin
    isBogus := true;
    f := 1.0;
 end;
end;

begin
  checkSingle(h.PixDim[1]);
  checkSingle(h.PixDim[2]);
  checkSingle(h.PixDim[3]);
  if (isBogus) then
    printf('Bogus PixDim repaired. Check dimensions and orientation.');
  isBogus := false;
  for i := 0 to 3 do begin
      if specialSingle(h.srow_x[i]) then isBogus := true;
      if specialSingle(h.srow_y[i]) then isBogus := true;
      if specialSingle(h.srow_z[i]) then isBogus := true;
  end;
  if (h.srow_x[0] = 0) and (h.srow_x[1] = 0) and (h.srow_x[2] = 0) then isBogus := true;
  if (h.srow_y[0] = 0) and (h.srow_y[1] = 0) and (h.srow_y[2] = 0) then isBogus := true;
  if (h.srow_z[0] = 0) and (h.srow_z[1] = 0) and (h.srow_z[2] = 0) then isBogus := true;
  if (h.srow_x[0] = 0) and (h.srow_y[0] = 0) and (h.srow_z[0] = 0) then isBogus := true;
  if (h.srow_x[1] = 0) and (h.srow_y[1] = 0) and (h.srow_z[1] = 0) then isBogus := true;
  if (h.srow_x[2] = 0) and (h.srow_y[2] = 0) and (h.srow_z[2] = 0) then isBogus := true;
  if (not isBogus) then exit;
  NII_SetIdentityMatrix(h);
  printf('Bogus header repaired. Check orientation.');
end;

//{$DEFINE DEBUG}
function TNIfTI.Load(niftiFileName: string; tarMat: TMat4; tarDim: TVec3i; isInterpolate: boolean; volumeNumber: integer = 0; isKeepContrast: boolean = false): boolean; overload;
var
   scaleMx: single;
   lLUTname: string;
begin
  {$IFDEF CACHEUINT8} //release cache, reload on next refresh
  fWindowMinCache8 := infinity;
  fCache8 := nil;
  {$ENDIF}
  fLabels.Clear;
  fBidsName := '';
  fFilename := niftiFileName;
  fVolumeDisplayed := volumeNumber;
  if fVolumeDisplayed < 0 then fVolumeDisplayed := 0;
  fIsOverlay := (tarDim.X) > 0;
  HiddenByCutout := not fIsOverlay;
  fShortName := changefileextX(extractfilename(fFilename),'');
  result := true;
  if niftiFileName = '+' then begin
    MakeBorg(4);
    fVolumeDisplayed := 0;
    fShortName := 'Borg';
    result := false;

  end else if not OpenNIfTI() then begin
     MakeBorg(64);
     fVolumeDisplayed := 0;
     fShortName := 'Borg';
     result := false;
  end;
  if (fHdr.datatype = kDT_RGB) and (fIsOverlay) then begin
     showmessage('Unable to load RGB image as overlay (overlays must be scalar).');
     exit(false);
  end;
  if (IsLabels) then begin
     if (fHdr.bitpix <= 16)  then begin
        LoadLabelsTxt(fFilename, fLabels);
        if (fLabels.Count < 1) and (( fHdr.vox_offset- fHdr.HdrSz) > 128) then
           LoadLabels(fFilename, fLabels, fHdr.HdrSz, round( fHdr.vox_offset)) ;
     end;
      if (fLabels.Count < 1) then
        fHdr.intent_code :=  kNIFTI_INTENT_NONE
      else begin
        lLUTname := changefileextX(fFilename,'.lut'); //file.nii.gz -> file.lut
        if not Fileexists(lLUTname) then
           lLUTname := changefileext(fFilename,'.lut'); //file.nii.gz -> file.nii.lut ;
        if Fileexists(lLUTname) then
           clut.LoadCustomLabelLut(lLUTname);
      end;
  end;
  fixBogusHeaders(fHdr);
  fHdrNoRotation := fHdr; //raw header without reslicing or orthogonal rotation
  if prod(tarDim) = 0 then //reduce size of huge background images
     if ShrinkLarge(fHdr,fRawVolBytes, MaxVox) then
        fVolumesLoaded := 1;
  scaleMx := max(max(abs(fHdr.Dim[1]*fHdr.PixDim[1]),abs(fHdr.Dim[2]*fHdr.pixDim[2])),abs(fHdr.Dim[3]*fHdr.pixDim[3]));
  if (scaleMx <> 0) then begin
    fScale.X := abs((fHdr.Dim[1]*fHdr.PixDim[1]) / scaleMx);
    fScale.Y := abs((fHdr.Dim[2]*fHdr.PixDim[2]) / scaleMx);
    fScale.Z := abs((fHdr.Dim[3]*fHdr.PixDim[3]) / scaleMx);
  end;
  fDim.x := fHdr.Dim[1];
  fDim.y := fHdr.Dim[2];
  fDim.z := fHdr.Dim[3];
  fPermInOrient := pti(1,2,3);
  fMat := SForm2Mat(fHdr);
  fMatInOrient := fMat;
  if fHdr.scl_slope = 0 then fHdr.scl_slope := 1;
  if (fHdr.datatype = kDT_UINT16) or (fHdr.datatype = kDT_INT32) or (fHdr.datatype = kDT_DOUBLE)  then
     Convert2Float();
  if prod(tarDim) > 0 then begin
    if IsLabels then
       VolumeReslice(tarMat, tarDim, false)
    else
       VolumeReslice(tarMat, tarDim, isInterpolate)
  end else
      VolumeReorient();
  if (isKeepContrast) then begin //do not change color settings when switching volumes in multi-volume overlay
    SetDisplayMinMax();
    exit;
  end;
  fMat := SForm2Mat(fHdr);
  fInvMat := fMat.inverse;
  if IsLabels then begin
    fAutoBalMin := 0;
    fAutoBalMax := 100;
    fMin := 0;
    fMax := 100;
    fWindowMin := 0;
    fWindowMax := 100;
    clut.SetLabels(niftiFileName);
    DisplayLabel2Uint8;
  end else if fHdr.datatype = kDT_UINT8 then
     initUInt8()
  else if fHdr.datatype = kDT_INT16 then
       initInt16()
  else if fHdr.datatype = kDT_FLOAT then
       initFloat32()
  else if fHdr.datatype = kDT_RGB then begin
       fAutoBalMin := 0;
       fAutoBalMax := 255;
       fMin := 0;
       fMax := 255;
       fWindowMin := 0;
       fWindowMax := 255;
  end else
      printf('Unsupported data format '+inttostr(fHdr.datatype));
  if (IsLabels) then
     //
  else if fAutoBalMin = fAutoBalMax then begin //e.g. thresholded data
     fAutoBalMin := fMin;
     fAutoBalMax := fMax;
     fWindowMin := fMin;
     fWindowMax := fMax;
  end else if (fIsOverlay) and (fAutoBalMin < -1.0) and (fAutoBalMax > 1.0) then begin
    fAutoBalMin := fAutoBalMax;
    fAutoBalMax := fAutoBalMax;
  end;
  initHistogram();
  if (IsLabels) then
     //
  else if (fHdr.cal_max > fHdr.cal_min) then begin
     if (fAutoBalMax > fAutoBalMin) and (((fHdr.cal_max - fHdr.cal_min)/(fAutoBalMax - fAutoBalMin)) > 5) then begin
          {$IFDEF Unix}writeln('Ignoring implausible cal_min..cal_max: FSL eddy?');{$ENDIF}
     end else begin
          fAutoBalMin := fHdr.cal_min;
          fAutoBalMax := fHdr.cal_max;
     end;
  end;
  fWindowMin := fAutoBalMin;
  fWindowMax := fAutoBalMax;
  if (CLUT.SuggestedMinIntensity < CLUT.SuggestedMaxIntensity) and (fMax > CLUT.SuggestedMinIntensity) and (fMin < CLUT.SuggestedMaxIntensity) then begin
     fWindowMin := CLUT.SuggestedMinIntensity;
     fWindowMax := CLUT.SuggestedMaxIntensity;
  end;
  if (fIsOverlay) and (fMin > -25) and (fMin < -5) and (fMax > 5) and (fMax < 25) and (fAutoBalMin < -0.5) and (fAutoBalMax > 0.5) then begin
     printf('Adjusting initial image intensity: Assuming statistical overlay.');
     fWindowMin := 1;
     fWindowMax := 1;
  end;
  SetDisplayMinMax();
end;

function TNIfTI.Load(niftiFileName: string): boolean; overload;
var
   tarMat: TMat4;
   tarDim: TVec3i;
begin
     tarMat := TMat4.Identity;
     tarDim := pti(0,0,0);
     result := Load(niftiFileName,tarMat, tarDim, false);
end;

constructor TNIfTI.Create(niftiFileName: string;  backColor: TRGBA; tarMat: TMat4; tarDim: TVec3i; isInterpolate: boolean; out isOK: boolean; lLoadFewVolumes: boolean = true; lMaxVox: integer = 640); overload;
{$IFNDEF CUSTOMCOLORS}
var
   i: integer;
{$ENDIF}
begin
 LoadFewVolumes := lLoadFewVolumes;
 MaxVox := lMaxVox;
 {$IFDEF CACHEUINT8}  //release cache, force creation on next refresh
 fWindowMinCache8 := infinity;
 fCache8 := nil;
 {$ENDIF}
 Nii_Clear(fHdrNoRotation);
 fVolumeDisplayed := 0;
 fVolumesLoaded := 1;
 fIsNativeEndian := true;
 fKnownOrientation := false;
 fIsOverlay := false;
 fIsDrawing := false;
 fCutoutLow := Vec3(0,0,0);
 fCutoutHigh := Vec3(0,0,0);
 fOpacityPct := 100;
 fRawVolBytes := nil;
 fVolRGBA := nil;
 fLabels := TStringList.Create;
 {$IFDEF CUSTOMCOLORS}
 clut := TCLUT.Create();
 clut.BackColor :=  backColor;

 {$ELSE}
 for i := 0 to 255 do
     fLUT[i] := setRGBA(i,i,i,i); //grayscale default
 {$ENDIF}
 //if niftiFileName = '-' then
 //    isOK := LoadEmpty(tarMat, tarDim)
 //else
  isOK := Load(niftiFileName, tarMat, tarDim, isInterpolate);
end;

constructor TNIfTI.Create(niftiFileName: string;  backColor: TRGBA; lLoadFewVolumes: boolean; lMaxVox: integer; out isOK: boolean); overload;
var
   tarMat: TMat4;
   tarDim: TVec3i;
begin
  tarMat := TMat4.Identity;
  tarDim := pti(0,0,0); //not an overlay: use source dimensions
  Create(niftiFileName, backColor, tarMat, tarDim, false, isOK, lLoadFewVolumes, lMaxVox);
end;

constructor TNIfTI.Create(tarMat: TMat4; tarDim: TVec3i); overload; //blank drawing
var
   isOK: boolean;
   backColor: TRGBA;
begin
 backColor := setRGBA(0,0,0,0);
 Create('-', backColor, tarMat, tarDim, false, isOK);
end;

constructor TNIfTI.Create(); overload;
var
   isOK: boolean;
   backColor: TRGBA;
begin
 backColor := setRGBA(0,0,0,0);
 Create('', backColor, true, 256, isOK);
end;

destructor TNIfTI.Destroy;
begin
  fLabels.Free;
  fRawVolBytes := nil;
  fVolRGBA := nil;
  fCache8 := nil;
  {$IFDEF CUSTOMCOLORS}
  clut.Free;
  {$ENDIF}
end;

end.

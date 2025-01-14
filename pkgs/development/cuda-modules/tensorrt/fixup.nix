{
  cudaVersion,
  final,
  hostPlatform,
  lib,
  mkVersionedPackageName,
  package,
  patchelf,
  requireFile,
  ...
}:
let
  inherit (lib)
    maintainers
    meta
    strings
    versions
    ;
in
finalAttrs: prevAttrs: {
  # Useful for inspecting why something went wrong.
  brokenConditions =
    let
      cudaTooOld = strings.versionOlder cudaVersion package.minCudaVersion;
      cudaTooNew =
        (package.maxCudaVersion != null) && strings.versionOlder package.maxCudaVersion cudaVersion;
      cudnnVersionIsSpecified = package.cudnnVersion != null;
      cudnnVersionSpecified = versions.majorMinor package.cudnnVersion;
      cudnnVersionProvided = versions.majorMinor finalAttrs.passthru.cudnn.version;
      cudnnTooOld =
        cudnnVersionIsSpecified && (strings.versionOlder cudnnVersionProvided cudnnVersionSpecified);
      cudnnTooNew =
        cudnnVersionIsSpecified && (strings.versionOlder cudnnVersionSpecified cudnnVersionProvided);
    in
    prevAttrs.brokenConditions
    // {
      "CUDA version is too old" = cudaTooOld;
      "CUDA version is too new" = cudaTooNew;
      "CUDNN version is too old" = cudnnTooOld;
      "CUDNN version is too new" = cudnnTooNew;
    };

  src = requireFile {
    name = package.filename;
    inherit (package) hash;
    message = ''
      To use the TensorRT derivation, you must join the NVIDIA Developer Program and
      download the ${package.version} TAR package for CUDA ${cudaVersion} from
      ${finalAttrs.meta.homepage}.

      Once you have downloaded the file, add it to the store with the following
      command, and try building this derivation again.

      $ nix-store --add-fixed sha256 ${package.filename}
    '';
  };

  # We need to look inside the extracted output to get the files we need.
  sourceRoot = "TensorRT-${finalAttrs.version}";

  buildInputs = prevAttrs.buildInputs ++ [finalAttrs.passthru.cudnn.lib];

  preInstall =
    let
      targetArch =
        if hostPlatform.isx86_64 then
          "x86_64-linux-gnu"
        else if hostPlatform.isAarch64 then
          "aarch64-linux-gnu"
        else
          throw "Unsupported architecture";
    in
    (prevAttrs.preInstall or "")
    + ''
      # Replace symlinks to bin and lib with the actual directories from targets.
      for dir in bin lib; do
        rm "$dir"
        mv "targets/${targetArch}/$dir" "$dir"
      done
    '';

  # Tell autoPatchelf about runtime dependencies.
  postFixup =
    let
      versionTriple = "${versions.majorMinor finalAttrs.version}.${versions.patch finalAttrs.version}";
    in
    (prevAttrs.postFixup or "")
    + ''
      ${meta.getExe' patchelf "patchelf"} --add-needed libnvinfer.so \
        "$lib/lib/libnvinfer.so.${versionTriple}" \
        "$lib/lib/libnvinfer_plugin.so.${versionTriple}" \
        "$lib/lib/libnvinfer_builder_resource.so.${versionTriple}"
    '';

  passthru = {
    useCudatoolkitRunfile = strings.versionOlder cudaVersion "11.3.999";
    # The CUDNN used with TensorRT.
    # If null, the default cudnn derivation will be used.
    # If a version is specified, the cudnn derivation with that version will be used,
    # unless it is not available, in which case the default cudnn derivation will be used.
    cudnn =
      let
        desiredName = mkVersionedPackageName "cudnn" package.cudnnVersion;
        desiredIsAvailable = final ? desiredName;
      in
      if package.cudnnVersion == null || !desiredIsAvailable then final.cudnn else final.${desiredName};
  };

  meta = prevAttrs.meta // {
    homepage = "https://developer.nvidia.com/tensorrt";
    maintainers = prevAttrs.meta.maintainers ++ [maintainers.aidalgol];
  };
}

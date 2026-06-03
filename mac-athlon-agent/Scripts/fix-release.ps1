$path = 'F:\mac-athlon-work\.github\workflows\build-release.yml'
$content = [System.IO.File]::ReadAllText($path)

$old = @'
      - name: Create GitHub Release
        if: startsWith(github.ref, 'refs/tags/')
        uses: softprops/action-gh-release@v2
        with:
          files: ${{ env.DMG_PATH }}
          generate_release_notes: true
'@

$new = @'
      - name: Create GitHub Release
        if: startsWith(github.ref, 'refs/tags/')
        uses: ncipollo/release-action@v1
        with:
          artifacts: ${{ env.DMG_PATH }}
          generateReleaseNotes: true
          token: ${{ secrets.GITHUB_TOKEN }}
'@

Write-Host "Old block to replace:"
Write-Host "---"
Write-Host $old
Write-Host "---"

Write-Host "Content contains softprops: $($content.Contains('softprops/action-gh-release@v2'))"
Write-Host "Content contains old block: $($content.Contains($old))"

$content = $content.Replace($old, $new)
[System.IO.File]::WriteAllText($path, $content, [System.Text.UTF8Encoding]::new($false))
Write-Host "Done."

// 把 macOS 的 .icns 转成 Windows 的 .ico。
//
// 现代 .icns 内部以多个不同分辨率的 PNG 区块存储(ic07/ic08/ic09/ic10 等)。
// 这里不依赖任何 .icns 解析库,直接在字节流里扫描 PNG 签名与 IEND 结束标记,
// 取出体积最大(即分辨率最高)的那张 PNG,再用 png2icons 生成多尺寸 .ico。
//
// 用法: node icns2ico.js <input.icns> <output.ico>

const fs = require('fs');
const png2icons = require('png2icons');

const [, , icnsPath, icoPath] = process.argv;
if (!icnsPath || !icoPath) {
  console.error('usage: node icns2ico.js <input.icns> <output.ico>');
  process.exit(1);
}

const buf = fs.readFileSync(icnsPath);
const PNG_SIG = Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);
const IEND = Buffer.from([0x49, 0x45, 0x4e, 0x44, 0xae, 0x42, 0x60, 0x82]);

const pngs = [];
let cursor = 0;
while (cursor < buf.length) {
  const start = buf.indexOf(PNG_SIG, cursor);
  if (start < 0) break;
  const end = buf.indexOf(IEND, start);
  if (end < 0) break;
  pngs.push(buf.subarray(start, end + IEND.length));
  cursor = end + IEND.length;
}

if (pngs.length === 0) {
  console.error('未在 .icns 中找到内嵌 PNG(可能是老式非 PNG 格式的 icns)');
  process.exit(2);
}

pngs.sort((a, b) => b.length - a.length);
const biggest = pngs[0];
console.log(`提取到 ${pngs.length} 个 PNG 区块,使用最大者(${biggest.length} 字节)生成 ICO`);

// createICO(input, scalingAlgorithm, numOfColors=0 不限, usePngInIco=false 用 BMP 兼容性最好)
const ico = png2icons.createICO(biggest, png2icons.BICUBIC, 0, false);
if (!ico) {
  console.error('png2icons 生成 ICO 失败');
  process.exit(3);
}
fs.writeFileSync(icoPath, ico);
console.log(`已写出 ${icoPath} (${ico.length} 字节)`);

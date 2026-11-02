# SeaVision V1.6.4 — GitHub 发布操作步骤

1. 解压 `SeaVision_FPGA_V164_GitHub.zip`，打开其中 `SeaVision_FPGA_V164_GitHub` 文件夹。
2. 访问 https://github.com/new ，登录 GitHub，输入仓库名 `SeaVision-FPGA`，Visibility 选 `Public`，不勾选初始化 README / .gitignore / License，点击 `Create repository`。
3. 在新建空仓库页面选择 `uploading an existing file`（或 `Add file` → `Upload files`）。
4. 将**解压后的文件夹内部的全部文件及子文件夹**拖到 GitHub 上传窗口（不要上传 ZIP 本身）；确认 README.md、user_source、docs 均已加入。
5. 在 `Commit changes` 中填写 `Initial SeaVision FPGA V1.6.4 source publication`，确认提交。
6. 刷新仓库首页，检查 README 图片与模块源码链接正确，核实没有上传厂商加密 IP、账号或本地私人文件。
7. 复制浏览器地址栏的仓库地址，例如 `https://github.com/<your-username>/SeaVision-FPGA`，粘贴到比赛平台的 `Github链接输入`。
8. 退出登录或使用无痕窗口打开该链接，确认评委无需登录即可访问。

注意：GitHub 浏览器上传限制每次最多100文件，每文件小于25MiB。本公开版经过筛选，不包含大体积生成数据库。V1.6.4 工程尚需修复黑盒错误并完成全工程验收，公开仓库的 README 已准确标明这一状态。

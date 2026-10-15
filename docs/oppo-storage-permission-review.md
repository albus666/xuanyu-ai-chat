# OPPO 存储权限移除说明

适用版本：1.0.73（构建号 74）。必须使用远程构建返回的新 APK 重新解析权限；旧包的权限不会因修改源码自动消失。

## 权限清单

新包不声明 `READ_EXTERNAL_STORAGE`、`WRITE_EXTERNAL_STORAGE`、`READ_MEDIA_IMAGES`、`READ_MEDIA_VIDEO` 或所有文件访问权限。Manifest 的移除规则同时阻止第三方依赖合并回存储读写权限。

## 读取文件

图片和视频使用系统 Photo Picker，不支持时回退到系统文档选择器。部落资料上传使用 ACTION_OPEN_DOCUMENT。仅处理用户主动选择的文件，不需要广泛存储读取权限。

## 保存图片

- Android 10 及以上：使用 MediaStore 保存本次生成的图片到相册“玄遇”目录。
- Android 9 及以下：使用 ACTION_CREATE_DOCUMENT 打开系统“另存为”，由用户选择 PNG 文件的保存位置。保存后提示“已保存图片文件”，不误称已添加到相册。
- 用户取消时取消导出；保存失败时不提示成功。旧系统不再申请存储权限，也不再直接写共享存储路径。

隐私弹窗、应用内隐私政策及线上网页同时更新为上述实际实现。

## 提交与设备核验

在 OPPO 后台替换安装包，重新解析权限并撤回旧的两项存储权限申请。设备核验应分别检查 Android 9 的保存位置选择、取消和文件结果，以及 Android 10 以上的直接相册保存。源码检查、自动化测试和 APK 检查不等同于真机或商店审核通过。

参考：<https://developer.android.com/training/data-storage/shared/documents-files>

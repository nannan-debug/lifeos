import Foundation

/// 模板：拷贝本文件为 Secrets.swift，填入真实 secret。
/// Secrets.swift 会被 .gitignore 忽略，不会提交到仓库。
///
/// 🔒 新协作者如何获取真实 secret：
///    - 找项目负责人（Anna）要
///    - 或用自己的 Cloudflare Worker 部署，生成自己的 secret
enum Secrets {
    /// Cloudflare Worker 鉴权 secret（对应 Worker 端 CLIENT_SECRET）
    static let aiClientSecret = "REPLACE_ME_WITH_REAL_SECRET"
}

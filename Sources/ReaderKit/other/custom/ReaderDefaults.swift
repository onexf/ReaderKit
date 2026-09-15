//
//  ReaderDefaults.swift
//  ReaderKit
//
//  Created by Asuna on 2025/09/21.
//

import UIKit

open class ReaderDefaults: NSObject {

    // MARK: 删除清空
    
    /// 清空
    public class func clear() {
        
        let defaults: UserDefaults = UserDefaults.standard
        let dictionary = defaults.dictionaryRepresentation()
        
        for key in dictionary.keys {
            
            defaults.removeObject(forKey: key)
            defaults.synchronize()
        }
    }
    
    /// 删除
    public class func remove(_ key: String) {
        let defaults: UserDefaults = UserDefaults.standard
        defaults.removeObject(forKey: key)
        defaults.synchronize()
    }
    
    // MARK: -- 存储
    
    /// 存储Object
    public class func setObject(_ value: Any?, _ key: String) {
        let defaults: UserDefaults = UserDefaults.standard
        defaults.set(value, forKey: key)
        defaults.synchronize()
    }
    
    /// 存储String
    public class func setString(_ value: String?, _ key: String) {
        ReaderDefaults.setObject(value, key)
    }
    
    /// 存储NSInteger
    public class func setInteger(_ value: NSInteger, _ key: String) {
        let defaults: UserDefaults = UserDefaults.standard
        defaults.set(value, forKey: key)
        defaults.synchronize()
    }
    
    /// 存储Bool
    public class func setBool(_ value: Bool, _ key: String) {
        let defaults: UserDefaults = UserDefaults.standard
        defaults.set(value, forKey: key)
        defaults.synchronize()
    }
    
    /// 存储Float
    public class func setFloat(_ value: Float, _ key: String) {
        let defaults: UserDefaults = UserDefaults.standard
        defaults.set(value, forKey: key)
        defaults.synchronize()
    }
    
    /// 存储TimeInterval
    public class func setTime(_ value: TimeInterval, _ key: String) {
        setInteger(NSInteger(value), key)
    }
    
    /// 存储Double
    public class func setDouble(_ value: Double, _ key: String) {
        let defaults: UserDefaults = UserDefaults.standard
        defaults.set(value, forKey: key)
        defaults.synchronize()
    }
    
    /// 存储URL
    public class func setURL(_ value: URL?, _ key: String) {
        let defaults: UserDefaults = UserDefaults.standard
        defaults.set(value, forKey: key)
        defaults.synchronize()
    }
    
    // MARK: -- 获取
    
    /// 获取Object
    public class func object(_ key: String) -> Any? {
        let defaults: UserDefaults = UserDefaults.standard
        return defaults.object(forKey: key)
    }
    
    /// 获取String
    public class func string(_ key: String) -> String {
        let defaults: UserDefaults = UserDefaults.standard
        let string = defaults.object(forKey: key) as? String
        return string ?? ""
    }
    
    /// 获取Bool
    public class func bool(_ key: String) -> Bool {
        let defaults: UserDefaults = UserDefaults.standard
        return defaults.bool(forKey: key)
    }
    
    /// 获取NSInteger
    public class func integer(_ key: String) -> NSInteger {
        let defaults: UserDefaults = UserDefaults.standard
        return defaults.integer(forKey: key)
    }
    
    /// 获取Float
    public class func float(_ key: String) -> Float {
        let defaults: UserDefaults = UserDefaults.standard
        return defaults.float(forKey: key)
    }
    
    /// 获取Double
    public class func double(_ key: String) -> Double {
        let defaults: UserDefaults = UserDefaults.standard
        return defaults.double(forKey: key)
    }
    
    /// 获取TimeInterval
    public class func time(_ key: String) -> TimeInterval {
        return TimeInterval(integer(key))
    }
    
    /// 获取URL
    public class func url(_ key: String) -> URL? {
        let defaults: UserDefaults = UserDefaults.standard
        return defaults.url(forKey: key)
    }
}

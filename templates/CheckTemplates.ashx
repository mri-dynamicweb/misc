<%@ WebHandler Language="C#" Class="Handler" %>

using System.Web;
using System.Text;
using System.IO;
using System.Collections.Generic;
using Dynamicweb.Rendering.Designer;
using System.Text.RegularExpressions;

public class Handler : IHttpHandler {
	private bool verbose = false;

	private HttpContext context;

	public void ProcessRequest(HttpContext context) {
		this.context = context;

		this.context.Response.ContentType = "text/html";

		this.verbose = this.context.Request["verbose"] == "true";

		var templates = GetTemplateFiles();

		Write(@"
<!DOCTYPE html>

<html xmlns='http://www.w3.org/1999/xhtml'>
	<head>
		<meta charset='utf-8'/>
		<title>Check Templates</title>
<style>
strong {
	color: red;
}
</style>
	</head>
<body>
<div id='content'>");

		Write("<h1>#templates: {0}</h1>", templates.Count);

		var numberOfSuccesses = 0;
		foreach (var template in templates) {
			if (!CheckIfCase(template)) continue;
			if (!CheckIf(template)) continue;
			numberOfSuccesses++;
		}

		if (numberOfSuccesses == templates.Count) {
			Write("All templates ok");
		}

		Write(@"</div>
</body>
</html>");
	}

	private bool CheckIfCase(TemplateFile template) {
		using (var reader = new System.IO.StreamReader(template.TemplateFileInfo.FullName)) {
			string line;
			var ifLevel = 0;
			var lineNumber = 0;
			var errors = new List<string>();
			var content = new StringBuilder();
			while ((line = reader.ReadLine()) != null) {
				lineNumber++;
				var matches = Regex.Matches(line, "<!--(?<stuff>@(?:(?:If( Not)?( Defined)?)|Else))", RegexOptions.IgnoreCase);
				foreach (Match match in matches) {
					var actual = match.Groups["stuff"].Value;
					var expected = System.Threading.Thread.CurrentThread.CurrentCulture.TextInfo.ToTitleCase(actual);
					if (!actual.Equals(expected)) {
						var message = string.Format("\"{0}\" must be \"{1}\" at line {2}", actual, expected, lineNumber);
						errors.Add(message);
					}
				}

				matches = Regex.Matches(line, "<!--(?<stuff>@EndIf)", RegexOptions.IgnoreCase);
				foreach (Match match in matches) {
					var actual = match.Groups["stuff"].Value;
					var expected = "@EndIf";
					if (!actual.Equals(expected)) {
						var message = string.Format("\"{0}\" must be \"{1}\" at line {2}", actual, expected, lineNumber);
						errors.Add(message);
					}
				}

				content.AppendFormat("{0,4}:\t{1}", lineNumber, line);
				content.AppendLine();
			}
			reader.Close();

			return ReportErrors(errors, template, content);
		}
	}

	private bool CheckIf(TemplateFile template) {
		using (var reader = new System.IO.StreamReader(template.TemplateFileInfo.FullName)) {
			string line;
			var ifLevel = 0;
			var lineNumber = 0;
			var errors = new List<string>();
			var errorLineNumber = -1;
			var content = new StringBuilder();
			while ((line = reader.ReadLine()) != null) {
				lineNumber++;
				line = Regex.Replace(line, "<!--@(?<keyword>If|Else|EndIf)", m => {
						var keyword = m.Groups["keyword"].Value;
						if (keyword == "If") {
							ifLevel += 1;
						}
						var result = string.Format("{0}[{1}]", m.Value, ifLevel);
						if (keyword == "EndIf") {
							ifLevel -= 1;
						}
						return m.Value; //result;
					});
				if (ifLevel < 0 && errorLineNumber < 0) {
					errorLineNumber = lineNumber;
					content.AppendFormat("{0,4}:\t[[strong]]{1}[[/strong]]", lineNumber, line);
				} else {
					content.AppendFormat("{0,4}:\t{1}", lineNumber, line);
				}
				content.AppendLine();
			}
			reader.Close();

			if (ifLevel != 0) {
				errors.Add(string.Format("Missing @{0} at {1}", (ifLevel > 0 ? "EndIf" : "If"), (errorLineNumber > 0) ? "line "+errorLineNumber : "end of file"));
			}

			return ReportErrors(errors, template, content);
		}
	}

	private bool ReportErrors(List<string> errors, TemplateFile template, StringBuilder content) {
		if (errors.Count > 0) {
			var templateUrl = template.TemplateName;
			Write("<fieldset>");
			Write("<legend>{0}</legend>", templateUrl);
			foreach (var error in errors) {
				Write("<div class='error'>{0}</div>", HtmlEncode(error));
			}

			var templateLocation = template.Location;

			// if (!Dynamicweb.Base.DWAssemblyVersionInformation().StartsWith("8.3")) {
			// 	templateLocation = Regex.Replace(templateLocation, "^/Files/", "", RegexOptions.IgnoreCase);
			// }

			if (template.TemplateFileInfo.FullName.StartsWith(Server.MapPath("~/Files/Templates/"))) {
				var editor = "FileManager_FileEditorV2.aspx";
				// editor = "Simple.aspx";
				var editUrl = string.Format("{0}://{1}/Admin/Filemanager/FileEditor/{2}?Folder={3}&amp;File={4}",
																		context.Request.Url.Scheme, context.Request.Url.Host, editor,
																		UrlEncode(templateLocation), UrlEncode(template.Name));
				Write("<div class='edit'><a target='edittemplate' href='{0}'>Edit template ({1})</a></div>", editUrl, templateUrl);
			}

			if (verbose) {
				Write("<hr/>");
				Write("<pre>{0}</pre>", Regex.Replace(HtmlEncode(content), @"\[{2,}(/?)([^\]]+)\]{2,}", "<$1$2>"));
			}
			Write("</fieldset>");
		}

		return errors.Count == 0;
	}

	private string HtmlEncode(object o) {
		return Server.HtmlEncode(o.ToString());
	}

	private string UrlEncode(object o) {
		return Server.UrlEncode(o.ToString());
	}

	private HttpServerUtility Server {
		get {
			return System.Web.HttpContext.Current.Server;
		}
	}

	private void Write(string s) {
		this.context.Response.Write(s);
	}

	private void WriteLine(string s) {
		this.context.Response.Write(s);
		Write("\n");
	}

	private void Write(string format, params object[] args) {
		this.context.Response.Write(string.Format(format, args));
	}

	private void WriteLine(string format, params object[] args) {
		Write(format, args);
		Write("\n");
	}

	private void Write(object o) {
		this.context.Response.Write(o.ToString());
	}

	private void WriteLine(object o) {
		Write(o);
		Write("\n");
	}

	private DirectoryInfo _templateDirectory = null;

	private DirectoryInfo TemplateDirectory {
		get {
			if (_templateDirectory == null) {
				var directory = new DirectoryInfo(Server.MapPath("~/Files/Templates/"));

				var request = System.Web.HttpContext.Current.Request;
				if (request["directory"] != null && Directory.Exists(request["directory"])) {
					directory = new DirectoryInfo(request["directory"]);
				}
				_templateDirectory = directory;
			}
			return _templateDirectory;
		}
	}

	private TemplateFileCollection GetTemplateFiles() {
		var collection = new TemplateFileCollection();
		GetTemplateFiles(TemplateDirectory, collection);
		return collection;
	}

	private void GetTemplateFiles(DirectoryInfo directory, TemplateFileCollection collection) {
		foreach (var file in TemplateFile.GetTemplateFiles(directory.FullName)) {
			if (file.FullName.IndexOf("parsed") < 0) {
				collection.Add(file);
			}
		}
		foreach (var dir in directory.GetDirectories()) {
			GetTemplateFiles(dir, collection);
		}
	}

	public bool IsReusable {
		get {
			return false;
		}
	}
}
